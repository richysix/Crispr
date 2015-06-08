#!/usr/bin/env perl

# PODNAME: get_pcr_primers_from_db.pl
# ABSTRACT: print PCR primers to file for ordering

use warnings;
use strict;
use Getopt::Long;
use autodie;
use Pod::Usage;

use Crispr::DB::DBConnection;

# get options
my %options;
get_and_check_options();

if( $options{debug} ){
    use Data::Dumper;
}

# connect to db
my $db_connection = Crispr::DB::DBConnection->new( $options{crispr_db}, );

# get adaptors
my $plate_adaptor = $db_connection->get_adaptor( 'plate' );
my $crRNA_adaptor = $db_connection->get_adaptor( 'crRNA' );

while(<>){
    chomp;
    my $plate_name = $_;
    my $primer_pair_plate = $plate_adaptor->fetch_primer_pair_plate_by_plate_name( $plate_name );
    my $cr_plate_name = $plate_name;
    $cr_plate_name =~ s/[a-z]$/-/xms;
    warn "Crispr plate name: $cr_plate_name\n" if $options{debug};
    my $crispr_plate = $plate_adaptor->fetch_crispr_plate_by_plate_name( $cr_plate_name );
    
    # set fill direction
    if( $options{fill_direction} ){
        $primer_pair_plate->fill_direction( $options{fill_direction} );
        $crispr_plate->fill_direction( $options{fill_direction} );
    }
    
    # get well range
    my $all_wells = $primer_pair_plate->plate_type eq '96'   ?  'A1-H12'
        :                                                       'A1-P24';
        
    my @well_ids;
    if( defined $options{well} ){
        @well_ids = @{ $options{well} };
    }
    elsif( defined $options{well_range} ){
        @well_ids = $primer_pair_plate->range_to_well_ids( $options{well_range} );
    }
    else {
        @well_ids = $primer_pair_plate->range_to_well_ids( $all_wells );
    }
    
    
    print join("\t", qw{ WellPosition Name Sequence Notes } ), "\n";
    foreach my $well_id ( @well_ids ){
        my $well = $primer_pair_plate->return_well( $well_id );
        my $cr_well = $crispr_plate->return_well( $well_id );
        my ( $primer_name, $primer_sequence, $crispr_name, );
        if( !defined $well->contents ){
            $primer_name = 'EMPTY';
            $primer_sequence = 'EMPTY';
            $crispr_name = 'EMPTY';
        }
        else{
            $primer_name = $well->contents->left_primer->primer_name;
            $primer_sequence = $well->contents->left_primer->sequence;
            $crispr_name = $cr_well->contents->name;
        }
        print join("\t", $well->position, $primer_name, $primer_sequence, $crispr_name, ), "\n";
    }
    
    foreach my $well_id ( @well_ids ){
        my $well = $primer_pair_plate->return_well( $well_id );
        my $cr_well = $crispr_plate->return_well( $well_id );
        my ( $primer_name, $primer_sequence, $crispr_name, );
        if( !defined $well->contents ){
            $primer_name = 'EMPTY';
            $primer_sequence = 'EMPTY';
            $crispr_name = 'EMPTY';
        }
        else{
            $primer_name = $well->contents->right_primer->primer_name;
            $primer_sequence = $well->contents->right_primer->sequence;
            $crispr_name = $cr_well->contents->name;
        }
        print join("\t", $well->position, $primer_name, $primer_sequence, $crispr_name, ), "\n";
    }
}

sub get_and_check_options {
    
    GetOptions(
        \%options,
        'well=s@',
        'well_range=s',
        'fill_direction=s',
		'crispr_db=s',
        'help',
        'man',
        'debug+',
        'verbose',
    ) or pod2usage(2);
    
    # Documentation
    if( $options{help} ) {
        pod2usage( -verbose => 0, exitval => 1, );
    }
    elsif( $options{man} ) {
        pod2usage( -verbose => 2 );
    }
    
    if( defined $options{well} && defined $options{well_range} ){
        my $msg = "Options --well and --well_range cannot be specified together!";
        pod2usage( $msg );
    }
    
    # default options    
    print "Settings:\n", map { join(' - ', $_, defined $options{$_} ? $options{$_} : 'off'),"\n" } sort keys %options if $options{verbose};
}

__END__

=pod

=head1 NAME

get_pcr_primers_from_db.pl

=head1 DESCRIPTION

Description

=cut

=head1 SYNOPSIS

    get_pcr_primers_from_db.pl [options] plate_names/plate_name_file
        --well_range            optional well range [default: all wells]
        --fill_direction        direction to go along the plate when printing [default: column]
        --crispr_db             database config file
        --help                  print this help message
        --man                   print the manual page
        --debug                 print debugging information
        --verbose               turn on verbose output


=head1 ARGUMENTS

=over

Either plate names supplied on the command_line or the name of a file to find plate names in.
REQUIRED.

=back

=head1 OPTIONS

=over 8

=item B<--well_range>

An optional well-range to print out such A01-A12.
Default: All wells whether full or not.

=item B<--fill_direction>

Must be either row or column.
Plate objects have a fill_direction.
e.g. A01-A02 will select wells A01 and A02 with a fill_direction of row,
but A01,B01,C01,D01,E01,F01,G01,H01 and A02 with a fill_direction of column,
Default: column

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