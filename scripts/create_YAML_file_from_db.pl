#!/usr/bin/env perl

# PODNAME: create_YAML_file_from_db.pl
# ABSTRACT: Script to create a sequence analysis YAML config file for a specific sequencing run from a CRISPR SQL database.

use warnings;
use strict;
use Getopt::Long;
use autodie;
use Pod::Usage;
use YAML::Tiny;

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
my $plex_adaptor = $db_connection->get_adaptor( 'plex' );
my $injection_pool_adaptor = $db_connection->get_adaptor( 'injection_pool' );
my $subplex_adaptor = $db_connection->get_adaptor( 'subplex' );
my $sample_adaptor = $db_connection->get_adaptor( 'sample' );
my $primer_pair_adaptor = $db_connection->get_adaptor( 'primer_pair' );
my $target_adaptor = $db_connection->get_adaptor( 'target' );

my $yaml = YAML::Tiny->new;
$yaml->[0]->{lane} = $options{lane};
$yaml->[0]->{name} = $options{plex};
$yaml->[0]->{plates} = [];

my $plex = $plex_adaptor->fetch_by_name( $options{plex} );
if( !$plex ){
    die "Could not find plex $options{plex} in the database!\n";
}
$yaml->[0]->{run_id} = $plex->run_id;

my $subplexes = $subplex_adaptor->fetch_all_by_plex( $plex );

# get sample info for each subplex
my %subplex_info;
my %crisprs_for_primer_pair;
my %info_for_well_block;
my %subplexes_for_wells;
my %gene_name_for_primer_pair;
foreach my $subplex ( @{$subplexes} ){
    my $subplex_id = $subplex->db_id;
    my $samples = $sample_adaptor->fetch_all_by_subplex( $subplex );
    # got through samples and add barcodes, well_ids and sample_names to yaml
    foreach my $sample ( @{$samples} ){
        push @{ $subplex_info{ $subplex_id }{ well_ids } }, $sample->well_id;
        push @{ $subplex_info{ $subplex_id }{ indices } }, $sample->barcode_id;
        push @{ $subplex_info{ $subplex_id }{ sample_names } }, $sample->sample_name;
    }
    
    my %pairs_seen;
    foreach my $guide_rna ( @{ $subplex->injection_pool->guideRNAs } ){
        my $crRNA_id = $guide_rna->crRNA->crRNA_id;
        # get illumina amplicon
        my @primer_pairs = grep { $_->type eq 'int-illumina_tailed' } @{ $primer_pair_adaptor->fetch_all_by_crRNA_id( $crRNA_id ) };
        if( scalar @primer_pairs > 1 ){
            die "Got more than one pair of int-illumina_tailed primers for ",
                $guide_rna->crRNA->name, "\n";
        }
        elsif( !@primer_pairs  ){
            die "Got no int-illumina_tailed primers for ",
                $guide_rna->crRNA->name, "\n";
        }
        else{
            my $pair_name = $primer_pairs[0]->pair_name;
            next if( exists $pairs_seen{$pair_name} );
            push @{ $subplex_info{ $subplex_id }{primer_pairs} }, $primer_pairs[0];
            push @{ $crisprs_for_primer_pair{ $pair_name } }, $guide_rna->crRNA;
            my $target = $target_adaptor->fetch_by_crRNA( $guide_rna->crRNA );
            $gene_name_for_primer_pair{$pair_name} = $target->gene_name;
            $pairs_seen{$pair_name} = 1;
        }
    }
    
    my $plate_num = $subplex->plate_num;
    my $well_ids = join(",", @{ $subplex_info{ $subplex_id }{ well_ids } } );
    push @{ $subplexes_for_wells{$plate_num}{ $well_ids } }, $subplex_id;
    $info_for_well_block{$plate_num}{ $well_ids }{ indices } = join(",", @{ $subplex_info{ $subplex_id }{ indices } } );
    $info_for_well_block{$plate_num}{ $well_ids }{ sample_names } = join(",", @{ $subplex_info{ $subplex_id }{ sample_names } } );
}

if( $options{debug} > 2 ){
    warn Dumper( %subplex_info, %crisprs_for_primer_pair, %info_for_well_block, %gene_name_for_primer_pair, );
    exit;
}

foreach my $plate_num ( sort { $a <=> $b } keys %subplexes_for_wells ){
    my $plate = {
        name => $plate_num,
        wells => [  ],
    };
    foreach my $well_ids ( sort keys %{$subplexes_for_wells{$plate_num}} ){
        my $well_block = {
            well_ids => $well_ids,
            indices => $info_for_well_block{$plate_num}{ $well_ids }{ 'indices' },
            sample_names => $info_for_well_block{$plate_num}{ $well_ids }{ 'sample_names' },
            plexes => [  ],
        };
        foreach my $subplex_id ( sort @{$subplexes_for_wells{$plate_num}{$well_ids}} ){
            my $subplex = {
                name => $subplex_id,
                region_info => [  ],
            };
            foreach my $primer_pair ( @{ $subplex_info{ $subplex_id }{primer_pairs} } ){
                my $pair_name = $primer_pair->pair_name;
                my $region_info = {
                    gene_name => $gene_name_for_primer_pair{$pair_name},
                    region => $primer_pair->pair_name,
                    crisprs => [ map { $_->name } @{$crisprs_for_primer_pair{$pair_name}} ],
                };
                push @{ $subplex->{region_info} }, $region_info;
            }
            
            push @{ $well_block->{plexes} }, $subplex;
        }
        push @{ $plate->{wells} }, $well_block;
    }
    
    push @{ $yaml->[0]->{plates} }, $plate;
}

if( $options{debug} ){
    warn Dumper( $yaml );
}

$yaml->write( $options{output_file} );

sub get_and_check_options {
    
    GetOptions(
        \%options,
        'plex=s',
        'lane=i',
		'crispr_db=s',
        'output_file=s',
        'help',
        'man',
        'debug+',
        'verbose',
    ) or pod2usage(2);
    
    # Documentation
    if( $options{help} ) {
        pod2usage(1);
    }
    elsif( $options{man} ) {
        pod2usage( -verbose => 2 );
    }
    
    if( !$options{plex} ){
        die "--option plex is required!\n";
    }
    # default options
    $options{lane} = $options{lane}    ?   $options{lane}  :   1;
    $options{plex} = lc( $options{plex} );
    $options{output_file} = $options{output_file}    ?   $options{output_file}  :   uc($options{plex}) . '.yml';
    $options{debug} = $options{debug}    ?   $options{debug}  :   0;
    
    print "Settings:\n", map { join(' - ', $_, defined $options{$_} ? $options{$_} : 'off'),"\n" } sort keys %options if $options{verbose};
}

__END__

=pod

=head1 NAME

create_YAML_file_from_manifest.pl

=head1 DESCRIPTION

Description

=cut

=head1 SYNOPSIS

    create_YAML_file_from_manifest.pl [options]
        --plex                  plex name REQUIRED
        --lane                  optional lane number [default: 1]
        --crispr_db             database config file
        --output_file           name for the YAML file
        --help                  print this help message
        --man                   print the manual page
        --debug                 print debugging information
        --verbose               turn on verbose output


=head1 ARGUMENTS

=over

=item B<--plex>

The name of the plex. REQUIRED.

=back

=head1 OPTIONS

=over 8

=item B<--output_file>

A name for the output YAML file. [default: PLEX.yml]

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