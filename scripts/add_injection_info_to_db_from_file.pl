#!/usr/bin/env perl

# PODNAME: add_injection_info_to_db_from_file.pl
# ABSTRACT: Add Information about guide RNA injections into a CRISPR SQL database.

use warnings;
use strict;
use Getopt::Long;
use autodie;
use Pod::Usage;
use English qw( -no_match_vars );
use List::MoreUtils qw( none );

use Crispr::DB::DBConnection;

# get options
my %options;
get_and_check_options();

# connect to db
my $db_connection = Crispr::DB::DBConnection->new( $options{crispr_db}, );
my $injection_pool_adaptor = $db_connection->get_adaptor( 'injection_pool' );
my $cas9_prep_adaptor = $db_connection->get_adaptor( 'cas9_prep' );
my $guide_rna_prep_adaptor = $db_connection->get_adaptor( 'guide_rna_prep' );
my $crRNA_adaptor = $db_connection->get_adaptor( 'crRNA' );

# parse input file, create GuideRNAPrep objects and add them to db
my @attributes = ( qw{ injection_id pool_name
    cas9_prep_id cas9_conc date line_injected line_raised
    sorted_by crispr_guides guide_RNA_concentrations } );
my @required_attributes = qw{ pool_name
    cas9_prep_id cas9_conc date line_injected
    crispr_guides guide_RNA_concentrations };

my $comment_regex = qr/#/;
my @columns;

my @injection_pools;
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
    
    # fetch cas9 prep from db with id
    $args{cas9_prep} = $cas9_prep_adaptor->fetch_by_id( $args{cas9_prep_id} );
    
    # Fetch crispr from db using either plate and well or name
    my @crRNAs;
    my @guide_rna_preps;
    my @guide_RNA_concentrations = split /,/, $args{guide_RNA_concentrations};
    foreach my $crispr_guide ( split /,/, $args{crispr_guides} ){
        my $crRNA;
        my $injection_concentration = scalar @guide_RNA_concentrations > 1 ?
                shift @guide_RNA_concentrations
                :   $guide_RNA_concentrations[0];
        
        if( $crispr_guide =~ m/\A ([0-9]+)                  # plate_number
                                        _                   # literal underscore 
                                        ([A-P])([0-9]+)     # well_id
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
        elsif( $crispr_guide =~ m/\A crRNA:             # prefix
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
                $crRNA = $crRNAs->[0];
            }
        }
        else{
            die join(q{ }, "Could not parse crispr guide name,",
                    $args{crispr_guide}, ), "\n";
        }
        push @crRNAs, $crRNA;
        
        my $guide_rna_preps = $guide_rna_prep_adaptor->fetch_all_by_crRNA_id( $crRNA->crRNA_id );
        # complain if there's more or less than one guide RNA prep
        if( scalar @{$guide_rna_preps} == 0 ){
            die join(q{ }, "No Guide RNA preps for crRNA,", $crRNA->name, ), "\n";
        }
        elsif( scalar @{$guide_rna_preps} > 1 ){
            die join(q{ }, "Got more than one Guide RNA prep for crRNA,", $crRNA->name, ), "\n";
        }
        $guide_rna_preps->[0]->injection_concentration( $injection_concentration );
        push @guide_rna_preps, $guide_rna_preps->[0];
    }
    $args{guideRNAs} = \@guide_rna_preps;
    if( exists $args{injection_pool_id} ){
        $args{db_id} = $args{injection_pool_id};
    }
    my $injection_pool = Crispr::DB::InjectionPool->new( %args );
    
    push @injection_pools, $injection_pool;
}

if( $options{debug} > 1 ){
    warn Dumper( @injection_pools );
}

# Add Injection Pools to db
eval {
    $injection_pool_adaptor->store_injection_pools( \@injection_pools );    
};

if( $EVAL_ERROR ){
    die "There was a problem storing one of the injection pools in the database.\n",
            "ERROR MSG:", $EVAL_ERROR, "\n";
}
else{
    print join("\n",
            map { join(q{ }, 'Injection Pool:',
                        $_->pool_name,
                        'was stored correctly in the database with id:',
                        $_->db_id, ) } @injection_pools,
    ), "\n";
}

sub get_and_check_options {
    
    GetOptions(
        \%options,
        'crispr_db=s',
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
    
    # default values
    $options{debug} = defined $options{debug} ? $options{debug} : 0;
    if( $options{debug} > 1 ){
        use Data::Dumper;
    }
    
    print "Settings:\n", map { join(' - ', $_, defined $options{$_} ? $options{$_} : 'off'),"\n" } sort keys %options if $options{verbose};
}

__END__

=pod

=head1 NAME

add_injection_info_to_db_from_file.pl

=head1 DESCRIPTION

Description

=cut

=head1 SYNOPSIS

    add_injection_info_to_db_from_file.pl [options] input file | STDIN
        --crispr_db             config file for connecting to the database
        --help                  print this help message
        --man                   print the manual page
        --debug                 print debugging information
        --verbose               turn on verbose output


=head1 ARGUMENTS

=over

Input file.
Tab separated file with information about Injection pools.
There must be a header line beginning with #.
Should contain the following columns:

=over

=item injection_pool - Str

=item cas9_prep_id - Int

=item cas9_conc - Float

=item date - Date (yyyy-mm-dd)

=item line_injected - Str

=item crispr_guides - Str (Comma-separated list of either PLATENUM_WELLID e.g. 7_A01 or crispr names e.g. crRNA:7:234567-234589:1)

=item guide_RNA_concentrations - Str (Comma-separated list of Floats)

=back

Optional columns are:

=over

=item injection_id - Int (database id)

=item line_raised - Str

=item sorted_by - Str

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

=item B<--debug>

Print debugging information.

=item B<--help>

Print a brief help message and exit.

=item B<--man>

Print this script's manual page and exit.

=back

=head1 DEPENDENCIES

None

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