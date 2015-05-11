#!/usr/bin/perl
# add_guide_RNA_preps_to_db_from_file.pl - quick description

use warnings;
use strict;
use Getopt::Long;
use autodie;
use Pod::Usage;
use English qw( -no_match_vars );
use List::MoreUtils qw( any none );

use Crispr::DB::DBConnection;
use Crispr::DB::GuideRNAPrep;
use Crispr::DB::GuideRNAPrepAdaptor;
use Labware::Well;

# get options
my %options;
get_and_check_options();

# connect to db
my $db_connection = Crispr::DB::DBConnection->new( $options{crispr_db}, );
my $guide_rna_prep_adaptor = $db_connection->get_adaptor( 'guide_rna_prep' );
my $crRNA_adaptor = $db_connection->get_adaptor( 'crRNA' );
my $plate_adaptor = $db_connection->get_adaptor( 'plate' );

# make a new plate if plate_name option specified
my $guide_rna_plate;
if( $options{plate_name} ){
    $guide_rna_plate = Crispr::Plate->new(
        plate_id => undef,
        plate_name => $options{plate_name},
        plate_category => 'guideRNA_prep',
        plate_type => $options{plate_type},
        fill_direction => $options{fill_direction},
        ordered => undef,
        received => undef,
    );
    # need to add plate to db to get plate_id
    #$plate_adaptor->store( $guide_rna_plate );
    eval{
        $plate_adaptor->store( $guide_rna_plate );
    };
    if( $EVAL_ERROR ){
        if( $EVAL_ERROR =~ m/PLATE\sALREADY\sEXISTS/xms ){
            warn join(q{ }, 'Guide RNA Plate', $guide_rna_plate->plate_name,
                      'already exists in the database. Using this plate to add oligos to...'
                     ), "\n";
        }
        else{
            die "There was a problem storing the construction oligos plate in the database.\n",
                    "ERROR MSG:", $EVAL_ERROR, "\n";
        }
    }
    else{
        print join(q{ }, $guide_rna_plate->plate_name,
                   'was stored correctly in the database with id:',
                   $guide_rna_plate->plate_id, ), "\n";
    }
    
}
else{
    # make a blank plate because the well requires it
    $guide_rna_plate = Crispr::Plate->new(
        plate_id => undef,
        plate_name => 'dummy_plate',
        plate_category => 'guideRNA_prep',
        plate_type => $options{plate_type},
        fill_direction => $options{fill_direction},
        ordered => undef,
        received => undef,
    );
    # don't add it to db and leave plate_id undef
}

# parse input file, create GuideRNAPrep objects and add them to db
my @attributes = ( qw{ guideRNA_prep_id crispr_guide guideRNA_type stock_concentration made_by date well_id } );
my @required_attributes = qw{ crispr_guide guideRNA_type stock_concentration made_by date };

my $comment_regex = qr/#/;
my @columns;

my @guide_rna_preps;
my $has_well_ids;
while(<>){
    my @values;
    
    chomp;
    if( $INPUT_LINE_NUMBER == 1 ){
        if( !m/\A $comment_regex/xms ){
            die "Input needs a header line starting with a #\n";
        }
        s|$comment_regex||xms;
        @columns = split /\t/, $_;
        foreach my $column_name ( @columns ){
            if( none { $column_name eq $_ } @attributes ){
                die "Could not recognise column name, ", $column_name, ".\n";
            }
        }
        foreach my $attribute ( @required_attributes ){
            if( none { $attribute eq $_ } @columns ){
                die "Missing required attribute: ", $attribute, ".\n";
            }
        }
        if( any { $_ eq 'well_id' } @columns ){
            $has_well_ids = 1;
            warn "Input has well ids.\n";
        }
        next;
    }
    else{
        @values = split /\t/, $_;
    }
    
    my %args;
    for( my $i = 0; $i < scalar @columns; $i++ ){
        if( $values[$i] eq 'NULL' ){
            $values[$i] = undef;
        }
        $args{ $columns[$i] } = $values[$i];
    }
    warn Dumper( %args ) if $options{debug} > 1;
    
    # Fetch crispr from db using either plate and well or name
    my $crRNA;
    if( $args{crispr_guide} =~ m/\A ([0-9]+)        # plate_number
                                    _               # literal underscore 
                                    ([A-P])([0-9]+) # well_id
                                    \z/xms ){
        # check column number is possible
        my $col_num = $3;
        if( $col_num > 24 ){
            die join(q{ }, "Column number of well id is too large,",
                    $1, $args{crispr_guide}, ), "\n";
        }
        $col_num = length $col_num == 1 ? '0' . $col_num : $col_num;
        my $well_id = $2 . $col_num;
        my $plate_num = $1;
        $crRNA = $crRNA_adaptor->fetch_by_plate_num_and_well( $plate_num, $well_id, );
    }
    elsif( $args{crispr_guide} =~ m/\A crRNA:       # prefix
                                    \w+:            # chr name
                                    \d+ - \d+       # start-end
                                    :\-*1           # strand
                                    \z/xms ){
        my $crRNAs = $crRNA_adaptor->fetch_by_name( $args{crispr_guide}, );
        if( scalar @{$crRNAs} != 1 ){
            die join(q{ }, "Crispr name,", $args{crispr_guide},
                    "is not unique. Try using plate number and well.", ), "\n";
        }
        else{
            $crRNA = $crRNA->[0];
        }
    }
    else{
        die join(q{ }, "Could not parse crispr guide name,",
                $args{crispr_guide}, ), "\n";
    }
    
    # If file has well ids make a well to add to the guideRNAPrep object
    my $well;
    if( $has_well_ids ){
        $well = Labware::Well->new(
            position => $args{well_id},
            plate => $guide_rna_plate,
            plate_type => $options{plate_type},
        );
    }
    
    if( exists $args{guide_rna_prep_id} ){
        $args{db_id} = $args{guide_rna_prep_id};
    }
    $args{crRNA} = $crRNA;
    my $guide_rna_prep = Crispr::DB::GuideRNAPrep->new( %args );
    if( $well ){ $guide_rna_prep->well( $well ); }
    
    push @guide_rna_preps, $guide_rna_prep;
}

if( $options{debug} > 1 ){
    warn Dumper( @guide_rna_preps );
}

# Add Guide RNA preps to db
eval {
    $guide_rna_prep_adaptor->store_guideRNA_preps( \@guide_rna_preps );    
};

if( $EVAL_ERROR ){
    die "There was a problem storing one of the crRNAs in the database.\n",
            "ERROR MSG:", $EVAL_ERROR, "\n";
}
else{
    print join("\n",
            map { join(q{ }, 'Guide RNA prep for',
                        $_->crRNA->name,
                        'was stored correctly in the database with id:',
                        $_->db_id, ) } @guide_rna_preps,
    ), "\n";
}

sub get_and_check_options {
    
    GetOptions(
        \%options,
        'crispr_db=s',
        'plate_name=s',
        'plate_type=s',
        'fill_direction=s',
        'help',
        'man',
        'debug+',
        'verbose',
    ) or pod2usage(2);
    
    # Documentation
    if( $options{help} ) {
        pod2usage( -verbose => 0, -exitval => 1, );
    }
    elsif( $options{man} ) {
        pod2usage( -verbose => 2 );
    }
    
    if( defined $options{plate_name} ){
        if( length( $options{plate_name} ) != 10 ){
            my $msg = "Plate name is limited to 10 characters";
            pod2usage( $msg );
        }
    }
    
    # defaults
    $options{plate_type} = $options{plate_type} ?   $options{plate_type}    :   '96';
    $options{fill_direction} = $options{fill_direction} ?   $options{fill_direction}    :   'column';
    $options{debug} = defined $options{debug} ? $options{debug} : 0;
    if( $options{debug} > 1 ){
        use Data::Dumper;
    }
    print "Settings:\n", map { join(' - ', $_, defined $options{$_} ? $options{$_} : 'off'),"\n" } sort keys %options if $options{verbose};
}

__END__

=pod

=head1 NAME

add_guide_RNA_preps_to_db_from_file.pl

=head1 DESCRIPTION

Script to add guide RNA preps to an SQL tracking database.
The guide RNAs must already exist in the database.

=cut

=head1 SYNOPSIS

    add_guide_RNA_preps_to_db_from_file.pl [options] input file | STDIN
        --crispr_db             config file for connecting to the database
        --plate_name            Optional name for a plate of guide RNA preps
        --plate_type            Type of plate (96 or 384) [default:96]
        --help                  print this help message
        --man                   print the manual page
        --debug                 print debugging information
        --verbose               turn on verbose output


=head1 ARGUMENTS

=over

Input file.
Tab separated file with information about guideRNA preps.
There must be a header line beginning with #.
Should contain the following columns:

=over

=item crispr_guide - Can be specified as PLATENUM_WELLID (e.g. 7_A01 ) or crRNA name (e.g. crRNA:7:234567-234589:1 ).

=item guideRNA_type - sgRNA or tracrRNA

=item stock_concentration - Float

=item made_by - String

=item date - Date (yyyy-mm-dd)

=back

Optional columns are:

=over

=item guideRNA_prep_id - Int (database id)

=item PAM - well_id e.g (A01)

=back

=back

=head1 OPTIONS

=over

=item B<--crispr_db file>

Database config file containing tab-separated key value pairs.
keys are:

=over

=item driver

mysql or sqlite

=item host

database host name (MySQL only)

=item port

database host port (MySQL only)

=item user

database host user (MySQL only)

=item pass

database host password (MySQL only)

=item dbname

name of the database

=item dbfile

path to database file (SQLite only)

=back

The values can also be set as environment variables
At the moment MySQL is assumed as the driver for this.

=over

=item MYSQL_HOST

=item MYSQL_PORT

=item MYSQL_USER

=item MYSQL_PASS

=item MYSQL_DBNAME

=back

=item B<--plate_name>

Optional name for a plate of guide RNA preps.
Plate name must be 10 characters at the moment.

=item B<--plate_type>

Type of plate (96 or 384 well) [default:96]

=item B<--debug>

Print debugging information.

=item B<--help>

Print a brief help message and exit.

=item B<--man>

Print this script's manual page and exit.

=back

=head1 DEPENDENCIES

Crispr

=head1 AUTHOR

=over 4

=item *

Richard White <richard.white@sanger.ac.uk>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by Genome Research Ltd.

This is free software, licensed under:

  The GNU General Public License, Version 3, June 2007

=cut