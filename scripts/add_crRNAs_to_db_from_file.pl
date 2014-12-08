#!/usr/bin/env perl
# add_crRNAs_to_db_from_file.pl

# PODNAME: add_crRNAs_to_db_from_file.pl
# ABSTRACT: Add crRNAs into CRISPR SQL database.

use warnings; use strict;
use Getopt::Long;
use English qw( -no_match_vars );
use Readonly;
use Pod::Usage;
use Data::Dumper;
use DateTime;
use List::MoreUtils qw( any none );
use Bio::EnsEMBL::Registry;
use Bio::Restriction::EnzymeCollection;
use Bio::Seq;

use Crispr;
use Crispr::crRNA;
use Crispr::OffTargetInfo;
use Crispr::OffTarget;
use Crispr::DB::DBConnection;
use Crispr::DB::crRNAAdaptor;
use Crispr::Plate;
use Labware::Well;

my %options;
get_and_check_options();

# check registry file and connect to Ensembl db
if( $options{registry_file} ){
    Bio::EnsEMBL::Registry->load_all( $options{registry_file} );
}
else{
    # if no registry file connect anonymously to the public server
    Bio::EnsEMBL::Registry->load_registry_from_db(
      -host    => 'ensembldb.ensembl.org',
      -user    => 'anonymous',
      -port    => 5306,
    );
}

my $ensembl_version = Bio::EnsEMBL::ApiVersion::software_version();
warn "Ensembl version: e", $ensembl_version, "\n" if $options{debug};
print "Ensembl version: e", $ensembl_version, "\n" if $options{verbose};

# Ensure database connection isn't lost; Ensembl 64+ can do this more elegantly
## no critic (ProhibitMagicNumbers)
if ( $ensembl_version < 64 ) {
## use critic
    Bio::EnsEMBL::Registry->set_disconnect_when_inactive();
}
else {
    Bio::EnsEMBL::Registry->set_reconnect_when_lost();
}

# get adaptors
my $slice_adaptor = Bio::EnsEMBL::Registry->get_adaptor( $options{species}, 'core', 'slice' );

# make design object
my $crispr_design = Crispr->new(
    species => $options{species},
    target_genome => $options{target_genome},
    #target_seq => $options{target_sequence},
    #five_prime_Gs => $options{num_five_prime_Gs},
    scored => 0,
    slice_adaptor => $slice_adaptor,
    debug => $options{debug},
);

# connect to db
my $db_connection = Crispr::DB::DBConnection->new( $options{crispr_db}, );

# get Target Adaptor using database adaptor
my $target_adaptor = $db_connection->get_adaptor( 'target' );
my $crRNA_adaptor = $db_connection->get_adaptor( 'crRNA' );
#my $primer_adaptor = $db_connection->get_adaptor( 'primer' );
#my $primer_pair_adaptor = $db_connection->get_adaptor( 'primer_pair' );
my $plate_adaptor = $db_connection->get_adaptor( 'plate' );

my @attributes = ( qw{ well_id target_name species requestor crRNA_name
    crRNA_chr crRNA_start crRNA_end crRNA_strand crRNA_score crRNA_sequence
    crRNA_oligo1 crRNA_oligo2 crRNA_off_target_score crRNA_off_target_counts
    crRNA_off_target_hits crRNA_coding_score crRNA_coding_scores_by_transcript
    crRNA_five_prime_Gs crRNA_plasmid_backbone crRNA_GC_content } );

my @required_attributes = qw{ target_name requestor crRNA_start crRNA_end crRNA_strand crRNA_sequence };

my $comment_regex = qr/#/;
my $has_well_ids;
my %well_id_for;
my @columns;
my @crisprs;
#my $primers;
while(<>){
    my @values;
    
    chomp;
    if( $INPUT_LINE_NUMBER == 1 ){
        if( !m/\A $comment_regex/xms ){
            die "Input needs a header line starting with a #";
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
            warn "Input has well ids. Option --fill_direction will be ignored even if specified.\n";
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
    
    if( !$args{'target_name'} || !$args{'requestor'} ){
        die "Must have a target name and a requestor for each crRNA to add to database.\n";
    }
    # fetch target from db
    ##  need to catch exceptions  ##
    my $target = $target_adaptor->fetch_by_name_and_requestor( $args{'target_name'}, $args{'requestor'} );
    $target->designed( $options{designed} );
    
    my %attributes = (
        crRNA_id => undef,
        target => $target,
        start => $args{crRNA_start},
        end => $args{crRNA_end},
        strand => $args{crRNA_strand},
        sequence => $args{crRNA_sequence},
    );
    if( defined $args{crRNA_chr} ){ $attributes{chr} = $args{crRNA_chr}; };
    
    my $crRNA = Crispr::crRNA->new( \%attributes );

    # off target info
    if( exists $args{'crRNA_off_target_hits'} && defined $args{'crRNA_off_target_hits'} ){
        $crRNA->off_target_hits(
            Crispr::OffTargetInfo->new(
                crRNA_name => $crRNA->name,
            )
        );
        my @off_targets = split /\|/, $args{'crRNA_off_target_hits'};
        if( defined $off_targets[0] && $off_targets[0] ne '' ){
            foreach ( split /\//, $off_targets[0] ){
                $crispr_design->make_and_add_off_target_from_position(
                    $crRNA, $_, 'exon',
                );
            }
        }
        if( defined $off_targets[1] && $off_targets[1] ne '' ){
            foreach ( split /\//, $off_targets[1] ){
                $crispr_design->make_and_add_off_target_from_position(
                    $crRNA, $_, 'intron',
                );
            }
        }
        if( defined $off_targets[2] && $off_targets[2] ne '' ){
            foreach ( split /\//, $off_targets[2] ){
                $crispr_design->make_and_add_off_target_from_position(
                    $crRNA, $_, 'nongenic',
                );
            }
        }
    }
    
    if( $options{debug} > 1 ){
        warn Dumper( $crRNA->off_target_hits );
    }

    if( exists $args{'crRNA_coding_scores_by_transcript'} &&
        defined $args{'crRNA_coding_scores_by_transcript'} ){
        foreach ( split /;/, $args{'crRNA_coding_scores_by_transcript'} ){
            $crRNA->coding_score_for( split /=/, $_ );
        }
    }
    
    if( exists $args{crRNA_five_prime_Gs} && defined $args{crRNA_five_prime_Gs} ){
        $crRNA->five_prime_Gs( $args{crRNA_five_prime_Gs} );
    }
    warn join("\t", $crRNA->info ), "\n" if $options{debug};
    
    $well_id_for{$crRNA->name} = $args{well_id};
    push @crisprs, $crRNA;
}

# check if there any crispr to add
if( !@crisprs ){
    die "There are no crispr RNAs to add to the database!\n";
}

# make a new plate to fill with crisprs
my $plate_name = 'CR_' . sprintf("%06d", $options{plate_num}) . '-';
my $crispr_plate = Crispr::Plate->new(
    plate_id => undef,
    plate_name => $plate_name,
    plate_category => 'crispr',
    plate_type => $options{plate_type},
    fill_direction => $options{fill_direction},
    ordered => $options{ordered},
    received => $options{received},
);

# fill plate with crisprs for adding to db
if( scalar @crisprs <= $crispr_plate->plate_type ){
    # add plate to db
    eval{
        $plate_adaptor->store( $crispr_plate );
    };
    if( $EVAL_ERROR ){
        if( $EVAL_ERROR =~ m/PLATE\sALREADY\sEXISTS/xms ){
            warn join(q{ }, 'Construction Plate', $crispr_plate->plate_name,
                      'already exists in the database. Using this plate to add oligos to...'
                     ), "\n";
        }
        else{
            die "There was a problem storing the construction oligos plate in the database.\n",
                    "ERROR MSG:", $EVAL_ERROR, "\n";
        }
    }
    else{
        print join(q{ }, $crispr_plate->plate_name,
                   'was stored correctly in the database with id:',
                   $crispr_plate->plate_id, ), "\n";
    }
    # fill wells of the plate
    if( $has_well_ids ){
        foreach my $crRNA ( @crisprs ){
            $crispr_plate->fill_well( $crRNA, $well_id_for{$crRNA->name} );
        }
    }
    else{
        $crispr_plate->fill_wells_from_first_empty_well( \@crisprs );
    }
}
else{
    die "More than one plate full of stuff!\n";
}

# store crRNAs in database
# return wells from plate and add to db
my $wells = $crispr_plate->return_all_non_empty_wells;
foreach my $well ( @{$wells} ){
    eval{
        $crRNA_adaptor->store( $well );
    };
    if( $EVAL_ERROR ){
        die "There was a problem storing one of the crRNAs in the database.\n",
                "ERROR MSG:", $EVAL_ERROR, "\n";
    }
    else{
        print join(q{ }, $well->contents->name,
            'was stored correctly in the database with id:',
            $well->contents->crRNA_id,
        ), "\n";
    }
}

if( $options{construction_oligos} ){
    # make a new plate to fill for construction oligos
    $plate_name = 'CR_' . sprintf("%06d", $options{plate_num}) . 'a';
    my $plate_cat = $options{construction_oligos} eq 't7_hairpin'  ?   't7_hairpin_oligos'
        :           'construction_oligos';
    my $oligo_plate = Crispr::Plate->new(
        plate_id => undef,
        plate_name => $plate_name,
        plate_category => $plate_cat,
        plate_type => $options{plate_type},
        fill_direction => $options{fill_direction},
        ordered => $options{ordered},
        received => $options{received},
    );
    
    # fill plate with crisprs for adding construction oligos to db
    if( scalar @crisprs <= $oligo_plate->plate_type ){
        # add plate to db
        eval{
            $plate_adaptor->store( $oligo_plate );
        };
        if( $EVAL_ERROR ){
            if( $EVAL_ERROR =~ m/PLATE\sALREADY\sEXISTS/xms ){
                warn join(q{ }, 'Construction Plate', $oligo_plate->plate_name,
                          'already exists in the database. Using this plate to add oligos to...'
                         ), "\n";
            }
            else{
                die "There was a problem storing the construction oligos plate in the database.\n",
                        "ERROR MSG:", $EVAL_ERROR, "\n";
            }
        }
        else{
            print join(q{ }, $oligo_plate->plate_name,
                       'was stored correctly in the database with id:',
                       $oligo_plate->plate_id, ), "\n";
        }
        # fill wells of the plate
        if( $has_well_ids ){
            foreach my $crRNA ( @crisprs ){
                $oligo_plate->fill_well( $crRNA, $well_id_for{$crRNA->name} );
            }
        }
        else{
            $oligo_plate->fill_wells_from_first_empty_well( \@crisprs );
        }
    }
    else{
        die "More than one plate full of stuff!\n";
    }
    
    # return wells from plate and add to db
    $wells = $oligo_plate->return_all_non_empty_wells;
    foreach my $well ( @{$wells} ){
        eval{
            $crRNA_adaptor->store_construction_oligos( $well, $options{construction_oligos} );
        };
        if( $EVAL_ERROR ){
            die "There was a problem storing one of the construction oligos in the database.\n",
                    "ERROR MSG:", $EVAL_ERROR, "\n";
        }
        else{
            print join(q{ }, 'Construction oligos for', $well->contents->name,
                    'were stored correctly in the database.'), "\n";
        }
    }
}

# add expression constructs to db
if( $options{expression_constructs} ){
    foreach my $suffix ( qw{ b c } ){
        my $construct_plate = Crispr::Plate->new(
            plate_id => undef,
            plate_category => 'expression_construct',
            plate_type => $options{plate_type},
            fill_direction => $options{fill_direction},
        );
        # add name to plate
        $plate_name = 'CR_' . sprintf("%06d", $options{plate_num}) . $suffix;
        $construct_plate->plate_name( $plate_name );
        
        # fill wells of the plate
        if( $has_well_ids ){
            foreach my $crRNA ( @crisprs ){
                $construct_plate->fill_well( $crRNA, $well_id_for{$crRNA->name} );
            }
        }
        else{
            $construct_plate->fill_wells_from_first_empty_well( \@crisprs );
        }
        
        # add plate to db
        eval{
            $plate_adaptor->store( $construct_plate );
        };
        if( $EVAL_ERROR ){
            if( $EVAL_ERROR =~ m/PLATE\sALREADY\sEXISTS/xms ){
                warn join(q{ }, 'Expression Plate', $construct_plate->plate_name,
                          'already exists in the database. Using this plate to add oligos to...'
                         ), "\n";
            }
            else{
                die "There was a problem storing the expression construct plate, ",
                    $construct_plate->plate_name, " in the database.\n",
                        "ERROR MSG:", $EVAL_ERROR, "\n";
            }
        }
        else{
            print join(q{ }, $construct_plate->plate_name,
                       'was stored correctly in the database with id:',
                       $construct_plate->plate_id, ), "\n";
        }
        
        # return wells from plate and add to db
        $wells = $construct_plate->return_all_non_empty_wells;
        foreach my $well ( @{$wells} ){
            eval{
                $crRNA_adaptor->store_expression_construct_info( $well );
            };
            if( $EVAL_ERROR ){
                die "There was a problem storing the expression construct info, ",
                    join(':', $construct_plate->plate_name, $well->position, ),
                    " in the database.\n",
                        "ERROR MSG:", $EVAL_ERROR, "\n";
            }
            else{
                print join(q{ }, 'Expression Constructs for', $well->contents->name,
                    join(q{}, '(', $well->plate->plate_name, ' id: ',
                        $well->plate->plate_id, ')', ),
                    'were stored correctly in the database.',
                ), "\n";
            }
        }
    }
}

# add coding scores and off_target_info
foreach my $crRNA ( @crisprs ){
    eval{
        $crRNA_adaptor->store_coding_scores( $crRNA );
    };
    if( $EVAL_ERROR ){
        die "There was a problem storing the coding score info for ",
            $crRNA->name, " in the database.\n",
            "ERROR MSG:", $EVAL_ERROR, "\n";
    }
    else{
        print join(q{ }, 'Coding score info for', $crRNA->name,
            'was stored correctly in the database.',
        ), "\n";
    }
    
    eval{
        $crRNA_adaptor->store_off_target_info( $crRNA );
    };
    if( $EVAL_ERROR ){
        die "There was a problem storing the off-target info for ",
            $crRNA->name, " in the database.\n",
            "ERROR MSG:", $EVAL_ERROR, "\n";
    }
    else{
        print join(q{ }, 'Off-target info for', $crRNA->name,
            'was stored correctly in the database.',
        ), "\n";
    }
}

sub get_and_check_options {
    
    GetOptions(
        \%options,
        'crispr_db=s',
        'plate_num=i',
        'plate_type=s',
        'fill_direction=s',
        'registry_file=s',
        'construction_oligos:s',
        'expression_constructs+',        
        'species=s',
        'target_genome=s',
        'annotation_file=s',
        'target_sequence=s',
        'num_five_prime_Gs=i',
        'designed=s',
        'ordered=s',
        'received=s',
        'debug+',
        'help',
        'man',
    ) or pod2usage(2);
    
    # Documentation
    if ($options{help}) {
        pod2usage(1);
    }
    elsif ($options{man}) {
        pod2usage( -verbose => 2 );
    }

    # Check options
    Readonly my @OLIGO_TYPES => ( qw{ cloning t7_hairpin } );
    Readonly my %OLIGO_TYPES => map { $_ => 1 } @OLIGO_TYPES;
    if( !defined $options{construction_oligos} ){
        $options{construction_oligos} = undef;
    }
    elsif( $options{construction_oligos} eq '' ){
        $options{construction_oligos} = $OLIGO_TYPES[0];
    }
    elsif( !exists $OLIGO_TYPES{ $options{construction_oligos} } ){
        die join(q{ }, 'Construction oligo type,', $options{construction_oligos}, 'is not a recognised type!', ), "\n",
            "Accepted types are: ", join(q{ }, sort keys %OLIGO_TYPES ), "\n";
    }
    
    if( !$options{designed} ){
        $options{designed} = DateTime->now();
    }
    elsif( $options{designed} !~ m/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/xms ){
        pod2usage( "The date supplied for option --designed is not a valid format\n Use YEAR-MONTH-DAY\n" );
    }
    else{
        $options{designed} = _parse_date_to_date_object( $options{designed} );
    }
    
    if( $options{ordered} ){
        if( $options{ordered} !~ m/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/xms ){
            pod2usage( "The date supplied for option --ordered is not a valid format\n Use YEAR-MONTH-DAY\n" );
        }
        else{
            $options{ordered} = _parse_date_to_date_object( $options{ordered} );
        }
    }
    
    if( $options{received} ){
        if( $options{received} !~ m/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/xms ){
            pod2usage( "The date supplied for option --received is not a valid format\n Use YEAR-MONTH-DAY\n" );
        }
        else{
            $options{received} = _parse_date_to_date_object( $options{received} );
        }
    }
    
    # defaults options
    $options{debug} = $options{debug}   ?   $options{debug} :   0;
    $options{species} = $options{species}   ?   $options{species} :   'zebrafish';
    $options{plate_num} = $options{plate_num}   ?   $options{plate_num} :   1;
    $options{plate_type} = $options{plate_type} ?   $options{plate_type}    :   '96';
    $options{fill_direction} = $options{fill_direction} ?   $options{fill_direction}    :   'column';
    
    return 1;
}

sub _parse_date_to_date_object {
    my ( $date ) = @_;
    
    $date =~ m/\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/xms;
    my $date_obj = DateTime->new(
        year       => $1,
        month      => $2,
        day        => $3,
    );
    return $date_obj;
}

__END__

=pod

=head1 NAME

add_crRNAs_to_db_from_file.pl

=head1 DESCRIPTION

Takes Information on crispr target sites and enter guide RNA info into a MySQL or SQLite database.

=head1 SYNOPSIS

    add_crRNAs_to_db_from_file.pl [options] filename(s) | target info on STDIN
        --crispr_db                     config file for connecting to the database
        --plate_num                     Plate number
        --plate_type                    Type of plate (96 or 384) [default:96]
        --fill_direction                row or column [default:column]
        --registry_file                 a registry file for connecting to the Ensembl database
        --construction_oligos           turns on adding construction oligos to the database for each crispr
                                        Also can dictate which type of oligos are added [default: cloning oligos]
        --expression_constructs         turns on adding expression constructs to the database for each crispr
        --designed                      date on which the crisprs were designed
        --ordered                       date on which the crisprs were ordered
        --received                      date on which the crisprs were received
        --help                          prints help message and exits
        --man                           prints manual page and exits
        --debug                         prints debugging information

=head1 REQUIRED ARGUMENTS

=over

=item B<input>

Information on crisprs. Can be a list of filenames or on STDIN.

Should contain the following columns: 
target_name requestor start end strand sequence

Optional columns are:
well_id species chr bwa_hits crRNA_coding_scores_by_transcript crRNA_five_prime_Gs 

=back

=head1 OPTIONS

=over 8

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

=item B<--plate_num integer>

Plate number to put construction oligos and expression constructs in.

=item B<--plate_type >

Type of plate (96 or 384 well) [default:96]

=item B<--fill_direction >

row or column [default:column]
fill_direction is ignored if well ids are explicitly supplied in the input.

=item B<--registry_file file>

a registry file for connecting to the Ensembl database

=item B<--construction_oligos>

If set, construction oligos are added to the database.
Also, controls which sort of oligos are added.
Default is 'cloning' oligos. Other option at the moment is 't7_hairpin'.

=item B<--expression_constructs>

If set, expression constructs are are added to the database.
By default, 2 duplicate plates are added as we routinely pick 2 colonies during cloning.

=item B<--designed >

date on which the crisprs were designed (YEAR-MONTH-DAY)

=item B<--ordered >

date on which the crisprs were ordered (YEAR-MONTH-DAY)

=item B<--received >

date on which the crisprs were received (YEAR-MONTH-DAY)

=item B<--debug>

Print debugging information.

=item B<--help>

Print a brief help message and exit.

=item B<--man>

Print this script's manual page and exit.

=back

=head1 AUTHOR

=over 4

=item *

Richard White <richard.white@sanger.ac.uk>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by Genome Research Ltd.

This is free software, licensed under:

  The GNU General Public License, Version 3, June 2007

