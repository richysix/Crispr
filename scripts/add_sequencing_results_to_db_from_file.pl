#!/usr/bin/env perl

# PODNAME: add_sequencing_results_to_db_from_file.pl
# ABSTRACT: Add information about samples and analysis information
# to a CRISPR SQL database from a sample manifext file.

use warnings;
use strict;
use Getopt::Long;
use autodie;
use Pod::Usage;
use English qw( -no_match_vars );
use Data::Dumper;
use Readonly;

use Crispr::DB::DBConnection;

# get options
my %options;
get_and_check_options();

# set threshold from options or default
Readonly my $READS_THRESHOLD => defined $options{reads_threshold} ?
    $options{reads_threshold}: 50;
Readonly my $PC_THRESHOLD => defined $options{pc_threshold} ?
    $options{pc_threshold} : 5;

# connect to db
my $db_connection = Crispr::DB::DBConnection->new( $options{crispr_db}, );
my $crRNA_adaptor = $db_connection->get_adaptor( 'crRNA' );
my $sample_adaptor = $db_connection->get_adaptor( 'sample' );
my $allele_adaptor = $db_connection->get_adaptor( 'allele' );


# Set up Sample and Allele Cache
my %crRNA_cache; #HASH keyed on crRNA_id (db id)
my %sample_cache; #HASH keyed on sample names
my %allele_number_for; #HASH keyed on variant (CHR:POS:REF:ALT)
my @samples;

# Read in variants
while(<>){
    my ( $plex_name, $plate_num, $analysis_id, $well_id, $sample_name,
        $gene_name, $group_num, $amplicon, $caller, $type, $crRNA_name,
        $chr, $pos, $ref, $alt, $reads_with_indel, $total_reads, $pc_indels,
        $consensus_start, $ref_consensus, $alt_consensus, ) = split /\t/;

    my $variant = join(":", $chr, $pos, $ref, $alt, );
    my $allele_number;
    if( exists $allele_number_for{ $variant } ){
        $allele_number = $allele_number_for{ $variant };
    }
    else{
        $allele_number = $options{allele_number};
        $allele_number_for{ $variant } = $options{allele_number};
        $options{allele_number}++;
    }

    # Make a New Allele object
    my $allele = Crispr::Allele->new(
        chr => $chr,
        pos => $pos,
        ref_allele => $ref,
        alt_allele => $alt,
        allele_number => $allele_number,
        percent_of_reads => sprintf('%.1f', $pc_indels*100),
    );

    # get Sample object
    my $sample;
    $sample_name =~ s/\A miseq[0-9]+_[0-9]+_//xms;
    warn 'SAMPLE_NAME: ', $sample_name;
    if( exists $sample_cache{ $sample_name } ){
        $sample = $sample_cache{ $sample_name };
    }
    else{
        # fetch sample from db
        $sample = $sample_adaptor->fetch_by_name( $sample_name );
        warn 'SAMPLE: ', Dumper( $sample );
        $sample->total_reads( $total_reads );
        $sample_cache{ $sample_name } = $sample;
    }

    # get crispr from sample object
    # Sample -> InjectionPool -> GuideRNAPreps -> crRNAs
    my $crispr;
    foreach my $guideRNA_prep ( @{ $sample->injection_pool->guideRNAs() } ){
        if( $guideRNA_prep->crRNA->name eq $crRNA_name ){
            $crispr = $guideRNA_prep->crRNA();
        }
    }

    # add crispr to allele and allele to sample
    $allele->add_crispr( $crispr );
    $sample->add_allele( $allele );
    exit;
    push @samples, $sample;
}


# go through samples
foreach my $sample ( @samples ){
    # add Alleles to db, including allele_to_crispr and sample_allele tables
    # total up percentage of indels and add to sequencing_results table
    my %sequencing_results;
    foreach my $allele ( @{ $sample->alleles } ){
        # add allele to db, this will also add crisprs to allele_to_crispr table
        $allele_adaptor->store( $allele );
        # add to percentages
        foreach my $crispr ( @{$allele->crisprs} ){
            $sequencing_results{ $crispr->crRNA_id }{'num_indels'}++;
            $sequencing_results{ $crispr->crRNA_id }{'total_percentage'} += $allele->percent_of_reads;
            if( $allele->percent_of_reads >
                $sequencing_results{ $crispr->crRNA_id }{'percentage_major_variant'} ){
                    $sequencing_results{ $crispr->crRNA_id }{'percentage_major_variant'} =
                        $allele->percent_of_reads;
            }
        }
    }
    # fill in sample_allele table
    $sample_adaptor->store_alleles_for_sample( $sample );

    # fill in sequencing_results table
    $sample_adaptor->store_sequencing_results( $sample, \%sequencing_results );
}

# get_and_check_options
#Usage       :   get_and_check_options();
#Purpose     :   Get command line options and process them
#Returns     :
#Parameters  :   None
#Throws      :   If plex_name is not set
#                If run_id is not set
#Comments    :

sub get_and_check_options {

    GetOptions(
        \%options,
        'crispr_db=s',
        'allele_number=i',
        'reads_threshold=i',
        'pc_threshold=f',
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

    $options{debug} = defined $options{debug} ? $options{debug} : 0;
    print "Settings:\n", map { join(' - ', $_, defined $options{$_} ? $options{$_} : 'off'),"\n" } sort keys %options if $options{verbose};
}

__END__

=pod

=head1 NAME

add_sequencing_results_to_db_from_file.pl

=head1 DESCRIPTION

Script to take a sequencing results file and add the information to an SQL database.

=cut

=head1 SYNOPSIS

    add_sequencing_results_to_db_from_file.pl [options] filename(s) | STDIN
        --crispr_db                         config file for connecting to the database
        --allele_number                     next unused sa allele number
        --reads_threshold                   number of reads a sample must have to pass
        --pc_threshold                      total percentage of indel reads for a sample to pass
        --help                              print this help message
        --man                               print the manual page
        --debug                             print debugging information
        --verbose                           turn on verbose output


=head1 ARGUMENTS

=over

=item B<input>

Sequencing results

Should contain the following columns:
sample_name, crRNA_id, chr, pos, ref_allele, alt_allele, reads_with_indel,
total_reads

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

=back

=over

=item B<--reads_threshold>

number of reads a sample must have covering a crispr location to pass
default: 50

=item B<--pc_threshold>

total percentage of indel reads for a given crispr for a sample to pass

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
