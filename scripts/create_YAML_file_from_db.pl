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
my $analysis_adaptor = $db_connection->get_adaptor( 'analysis' );
my $sample_adaptor = $db_connection->get_adaptor( 'sample' );
my $sample_amplicon_adaptor = $db_connection->get_adaptor( 'sample_amplicon' );
my $primer_pair_adaptor = $db_connection->get_adaptor( 'primer_pair' );
my $target_adaptor = $db_connection->get_adaptor( 'target' );
my $crRNA_adaptor = $db_connection->get_adaptor( 'crRNA' );

my $yaml = YAML::Tiny->new;
$yaml->[0]->{lane} = $options{lane};
$yaml->[0]->{name} = $options{plex};
$yaml->[0]->{plates} = [];

my $plex = $plex_adaptor->fetch_by_name( $options{plex} );
if( !$plex ){
    die "Could not find plex $options{plex} in the database!\n";
}
$yaml->[0]->{run_id} = $plex->run_id;

my $analyses = $analysis_adaptor->fetch_all_by_plex( $plex );

# get sample info for each analysis
my %analysis_info;
my %crisprs_for_primer_pair;
my %info_for_well_block;
my %analyses_for_wells;
my %gene_name_for_primer_pair;
foreach my $analysis ( @{$analyses} ){
    my $analysis_id = $analysis->db_id;
    my $sample_amplicons = $sample_amplicon_adaptor->fetch_all_by_analysis( $analysis );
    # go through samples and add barcodes, well_ids and sample_names to yaml
    my %pairs_seen;
    my %crisprs_seen;
    my %plate_nums;
    foreach my $sample_amplicon ( @{$sample_amplicons} ){
        $plate_nums{$sample_amplicon->plate_number} = 1;
        push @{ $analysis_info{ $analysis_id }{ well_ids } }, $sample_amplicon->well_id;
        push @{ $analysis_info{ $analysis_id }{ indices } }, $sample_amplicon->barcode_id;
        push @{ $analysis_info{ $analysis_id }{ sample_names } }, $sample_amplicon->sample_name;
        
        foreach my $primer_pair ( @{$sample_amplicon->amplicons} ){
            next if $primer_pair->type ne 'int-illumina_tailed';
            next if( exists $pairs_seen{$primer_pair->pair_name} );
            push @{ $analysis_info{ $analysis_id }{primer_pairs} }, $primer_pair;
            
            foreach my $crispr ( @{ $crRNA_adaptor->fetch_all_by_primer_pair( $primer_pair ) } ){
                if( !exists $crisprs_seen{$primer_pair->pair_name}{$crispr->name} ){
                    push @{ $crisprs_for_primer_pair{ $analysis_id }{ $primer_pair->pair_name } }, $crispr;
                    my $target = $target_adaptor->fetch_by_crRNA( $crispr );
                    $gene_name_for_primer_pair{ $analysis_id }{$primer_pair->pair_name} = $target->gene_name || $target->target_name;
                    $crisprs_seen{$primer_pair->pair_name}{$crispr->name} = 1;
                }
            }
            $pairs_seen{$primer_pair->pair_name} = 1;
        }
    }
    
    my $plate_num;
    if( keys %plate_nums != 1 ){
        die "number of plate numbers is wrong!\n", join("\t", keys %plate_nums );
    }
    else{
        $plate_num = ( keys %plate_nums )[0];
    }
    
    my $well_ids = join(",", @{ $analysis_info{ $analysis_id }{ well_ids } } );
    push @{ $analyses_for_wells{$plate_num}{ $well_ids } }, $analysis_id;
    $info_for_well_block{$plate_num}{ $well_ids }{ indices } = join(",", @{ $analysis_info{ $analysis_id }{ indices } } );
    $info_for_well_block{$plate_num}{ $well_ids }{ sample_names } = join(",", @{ $analysis_info{ $analysis_id }{ sample_names } } );
}

if( $options{debug} > 2 ){
    warn Dumper( %analysis_info, %crisprs_for_primer_pair, %info_for_well_block, %gene_name_for_primer_pair, );
    exit;
}

foreach my $plate_num ( sort { $a <=> $b } keys %analyses_for_wells ){
    my $plate = {
        name => $plate_num,
        wells => [  ],
    };
    foreach my $well_ids ( sort keys %{$analyses_for_wells{$plate_num}} ){
        my $well_block = {
            well_ids => $well_ids,
            indices => $info_for_well_block{$plate_num}{ $well_ids }{ 'indices' },
            sample_names => $info_for_well_block{$plate_num}{ $well_ids }{ 'sample_names' },
            plexes => [  ],
        };
        foreach my $analysis_id ( sort @{$analyses_for_wells{$plate_num}{$well_ids}} ){
            my $analysis = {
                name => $analysis_id,
                region_info => [  ],
            };
            foreach my $primer_pair ( @{ $analysis_info{ $analysis_id }{primer_pairs} } ){
                my $pair_name = $primer_pair->pair_name;
                my $region_info = {
                    gene_name => $gene_name_for_primer_pair{ $analysis_id }{$pair_name},
                    region => $primer_pair->pair_name,
                    crisprs => [ map { $_->name } @{$crisprs_for_primer_pair{ $analysis_id }{$pair_name}} ],
                };
                push @{ $analysis->{region_info} }, $region_info;
            }
            
            push @{ $well_block->{plexes} }, $analysis;
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
    $options{output_file} = $options{output_file}    ?   $options{output_file}  :   lc($options{plex}) . '.yml';
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

=item B<--lane>

Lane number. Default = 1.

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