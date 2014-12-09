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

my $yaml = YAML::Tiny->new;
$yaml->[0]->{lane} = $options{lane};
$yaml->[0]->{name} = $options{plex};
$yaml->[0]->{plates} = [];

# get info from db
my $dbh = $db_connection->connection->dbh();

my $sql = <<'END_SQL';
SELECT run_id
FROM plex
WHERE plex_name = ?;
END_SQL

my $sth = $dbh->prepare( $sql );
$sth->execute( $options{plex}, );
while( my @fields = $sth->fetchrow_array ){
    $yaml->[0]->{run} = $fields[0];
}
if( !$yaml->[0]->{run} ){
    die "Could not find plex $options{plex} in the database!\n";
}

$sql = <<'END_SQL';
SELECT subplex_id, plate_num,
    concat_ws(":", pp.chr, concat_ws("-", pp.start, pp.end ), pp.strand ) as amplicon,
    crRNA_name
FROM plex, subplex sub, injection i, injection_pool ip,
    crRNA cr, amplicon_to_crRNA amp, primer_pair pp
WHERE plex.plex_id = sub.plex_id AND
    i.injection_id = sub.injection_id AND
    i.injection_id = ip.injection_id AND
    ip.crRNA_id = cr.crRNA_id AND
    cr.crRNA_id = amp.crRNA_id AND
    amp.primer_pair_id = pp.primer_pair_id AND
    pp.type = 'illumina_tailed' AND
    plex.plex_name = ?;
END_SQL

$sth = $dbh->prepare( $sql );
$sth->execute( $options{plex}, );

my %subplex_info;
my %crisprs_for_amplicon;
my %crisprs_for_amplicon_seen;
my %amplicon_for_subplex_seen;
while( my @fields = $sth->fetchrow_array ){
    my ( $subplex_id, $plate_num, $amplicon, $crRNA_name, ) = @fields;
    $subplex_info{ $subplex_id }{plate_num} = $plate_num;
    if( !exists $amplicon_for_subplex_seen{ $subplex_id }{ $amplicon } ){
        $amplicon_for_subplex_seen{ $subplex_id }{ $amplicon } = 1;
        push @{ $subplex_info{ $subplex_id }{ amplicons } }, $amplicon;
    }
    if( !exists $crisprs_for_amplicon_seen{$amplicon}{$crRNA_name} ){
        $crisprs_for_amplicon_seen{$amplicon}{$crRNA_name} = 1;
        push @{ $crisprs_for_amplicon{$amplicon} }, $crRNA_name;
    }
}

# get sample info
$sql = <<'END_SQL';
SELECT well, barcode_number, sample_name
FROM sample
WHERE subplex_id = ?;
END_SQL

$sth = $dbh->prepare( $sql );

my %subplexes_for_wells;
my %info_for_well_block;
foreach my $subplex_id ( keys %subplex_info ){
    $sth->execute( $subplex_id );
    while( my @fields = $sth->fetchrow_array ){
        push @{ $subplex_info{ $subplex_id }{ well_ids } }, $fields[0];
        push @{ $subplex_info{ $subplex_id }{ indices } }, $fields[1];
        push @{ $subplex_info{ $subplex_id }{ sample_names } }, $fields[2];
    }
    
    my $plate_num = $subplex_info{ $subplex_id }{plate_num};
    my $well_ids = join(",", @{ $subplex_info{ $subplex_id }{ well_ids } } );
    push @{ $subplexes_for_wells{$plate_num}{ $well_ids } }, $subplex_id;
    $info_for_well_block{$plate_num}{ $well_ids }{ indices } = join(",", @{ $subplex_info{ $subplex_id }{ indices } } );
    $info_for_well_block{$plate_num}{ $well_ids }{ sample_names } = join(",", @{ $subplex_info{ $subplex_id }{ sample_names } } );
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
            foreach my $amplicon ( @{ $subplex_info{ $subplex_id }{amplicons} } ){
                # fetch gene_name from id
                $sql = <<'END_SQL';
    SELECT gene_name
    FROM target t, crRNA cr
    WHERE t.target_id = cr.target_id AND
        cr.crRNA_name = ?;
END_SQL
                # prepare query
                $sth = $dbh->prepare( $sql );
                my %gene_names;
                foreach my $crRNA_name ( @{ $crisprs_for_amplicon{$amplicon} } ){
                    $sth->execute( $crRNA_name );
                    while( my @fields = $sth->fetchrow_array ){
                        if( defined $fields[0] ){
                            $gene_names{ $fields[0] } = 1;
                        }
                        else{
                            $gene_names{ 'unknown' } = 1;
                        }
                    }
                }
                if( scalar keys %gene_names > 1 ){
                    die "Got more than 1 gene name for a single amplicon!\n",
                        join("\t", $plate_num, $well_ids, $subplex_id,
                                $amplicon,
                                join(",", @{ $crisprs_for_amplicon{$amplicon} }),
                            ), "\n";
                }
                my $region_info = {
                    gene_name => ( keys %gene_names )[0],
                    region => $amplicon,
                    crisprs => [ @{$crisprs_for_amplicon{$amplicon}} ],
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