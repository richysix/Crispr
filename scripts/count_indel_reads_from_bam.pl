#!/usr/bin/env perl
# PODNAME: count_indel_reads_from_bam.pl
# ABSTRACT: call and count indels from sample bam files

## Author         : rw4
## Maintainer     : rw4
## Created        : 2014-06-09

use warnings;
use strict;
use Getopt::Long;
use autodie qw(:all);
use Pod::Usage;
use Carp;
use YAML::Tiny;
use Readonly;
use English qw( -no_match_vars );
use File::Spec;
use File::Path qw(make_path);
use List::Util qw(sum);
use File::Which;
use DateTime;
use Storable;
use IO::Handle;
use Hash::Merge;

use Crispr;
use Tree::GenomicIntervalTree;
use Labware::Plate;
use Bio::DB::Sam;
use Bio::DB::Bam::Alignment;

my $date_obj = DateTime->now();
my $todays_date = $date_obj->ymd( q{} );

# get options
my %options;
get_and_check_options();

if( $options{debug} ){ use Data::Dumper; }
Readonly my $INTERVAL_EXTENDER => $options{overlap_threshold} ? $options{overlap_threshold} : 10;
Readonly my $COVERAGE_FILTER => !defined $options{overlap_threshold} ? 0
    :   $options{overlap_threshold} == 0 ? 10
    :   $options{overlap_threshold};

# For merging calls
Hash::Merge::specify_behavior(
    {
        SCALAR => {
            SCALAR => sub { $_[0] + $_[1] },    # Add scalars
            ARRAY  => sub { undef },
            HASH   => sub { undef },
        },
        ARRAY => {
            SCALAR => sub { undef },
            ARRAY  => sub { [ @{ $_[0] }, @{ $_[1] } ] },  # Join arrays
            HASH   => sub { undef },
        },
        HASH => {
            SCALAR => sub { undef },
            ARRAY  => sub { undef },
            HASH => sub { Hash::Merge::_merge_hashes( $_[0], $_[1] ) },
        },
    },
    'consensus',
);
my $hash_merge_consensus = Hash::Merge->new('consensus');

# make new Crispr object
my $crispr_design;
if( exists $options{reference} ){
    $crispr_design = Crispr->new(
        target_genome => $options{reference},
    );
}
else{
    $crispr_design = Crispr->new();
}
# make new genomic trees for crisprs and regions
my $crispr_tree = Tree::GenomicIntervalTree->new();
my $crispr_pair_tree = Tree::GenomicIntervalTree->new();

# get info from YAML file
# open and parse regions/crisprs file
my %crisprs_for_groups;
my %groups_for_crisprs;
my $yaml_file = shift @ARGV;
my $err_msg = "No YAML file has been supplied!\n";
pod2usage( $err_msg ) if( !$yaml_file );
my $plex_info = parse_yaml_file( $yaml_file );

# open output file
if( !-e $options{output_directory} ){
    make_path( $options{output_directory} );
}
if( !$options{output_file} ){
    $options{output_file} = $plex_info->{name} . '.txt'
}
my $outfile = File::Spec->catfile( $options{output_directory}, $options{output_file} );
open my $out_fh, '>', $outfile;
$out_fh->autoflush( 1 );

# create directory for bam files
my $output_bam_dir = File::Spec->catfile( $options{output_directory}, 'bams' );
# check whether directory already exists and create it if not
if( !-e $output_bam_dir ){
    my @created_dirs = make_path( $output_bam_dir );
    if( !@created_dirs ){
        die join(q{ }, "Could not create bams directory in",
                $options{output_directory}, "for output bam files!" ), "\n";
    }
}


# set up global types array
Readonly my @TYPES = ( qw{ D SI LI INT_final } );

# go through all the sample bams from the yaml file
my ( $results, $outliers, );
my %variants_seen;
print "CIGAR string analysis...\n" if $options{verbose};

# retrieve CIGAR data from disk if it exists
my $prefix = exists $plex_info->{prefix} ?   $plex_info->{prefix} :   $plex_info->{name};
my $combined_results_filename = File::Spec->catfile( $options{output_directory}, $prefix . '.combined_results.pd' );
my $cigar_pindel_results_filename = File::Spec->catfile( $options{output_directory}, $prefix . '.cigar_pindel_results.pd' );
my $cigar_filename = File::Spec->catfile( $options{output_directory}, $prefix . '.cigar_results.pd' );
my $data_object;
my $no_combined;
my $no_cigar_pindel;
my $no_cigar;
if( -e $combined_results_filename && -s $combined_results_filename ){
    eval {
        $data_object = retrieve( $combined_results_filename );
    };
    if( !$data_object || $EVAL_ERROR ){
        warn "There was a problem retrieving the combined results from disk. Continuing...\n",
            $EVAL_ERROR, "\n";
        $no_combined = 1;
    }
    elsif( !exists $data_object->{results} || !exists $data_object->{results} ){
        warn "There was a problem retrieving the CIGAR results from disk. Continuing...\n",
            $EVAL_ERROR, "\n";
        $no_combined = 1;
    }
}

if( !$data_object && -e $cigar_pindel_results_filename && -s $cigar_pindel_results_filename ){
    $no_combined = 1;
    eval {
        $data_object = retrieve( $cigar_pindel_results_filename );
    };
    if( !$data_object || $EVAL_ERROR ){
        warn "There was a problem retrieving the CIGAR-PINDEL results from disk. Continuing...\n",
            $EVAL_ERROR, "\n";
        $no_cigar_pindel = 1;
    }
    elsif( !exists $data_object->{results} || !exists $data_object->{results} ){
        warn "There was a problem retrieving the CIGAR-PINDEL results from disk. Continuing...\n",
            $EVAL_ERROR, "\n";
        $no_cigar_pindel = 1;
    }
}

if( !$data_object && -e $cigar_filename && -s $cigar_filename ){
    $no_combined = 1;
    $no_cigar_pindel = 1;
    eval {
        $data_object = retrieve( $cigar_filename );
    };
    if( !$data_object || $EVAL_ERROR ){
        warn "There was a problem retrieving the CIGAR results from disk. Continuing...\n",
            $EVAL_ERROR, "\n";
        $no_cigar = 1;
    }
    elsif( !exists $data_object->{results} || !exists $data_object->{results} ){
        warn "There was a problem retrieving the CIGAR results from disk. Continuing...\n",
            $EVAL_ERROR, "\n";
        $no_cigar = 1;
    }
}

if( !$data_object ){
    $no_combined = 1;
    $no_cigar_pindel = 1;
    $no_cigar = 1;
}

Readonly my $DOWNSAMPLE_LIMIT => 200;

if( $no_combined ){
    if( $no_cigar_pindel ){
        if( $no_cigar ){
            foreach my $plate ( @{ $plex_info->{plates} } ){
                print "Plate: ", $plate->{name}, "\n" if $options{verbose};
                warn "Plate: ", $plate->{name}, "\n" if $options{debug};
                foreach my $well_block ( @{ $plate->{wells} } ){
                    foreach my $plex ( @{$well_block->{plexes}} ){
                        print "Analysis: ", $plex->{name}, "\n" if $options{verbose};
                        warn "Analysis: ", $plex->{name}, "\n" if $options{debug};
                        # counter
                        my $i = 0;
                        my @indices;
                        # check for indices in the YAML hash. 
                        if( exists $well_block->{indices} ){
                            @indices = split /,/, $well_block->{indices};
                        }
                        foreach my $sample ( @{ $well_block->{sample_names} } ){
                            my $sample_name = join("_", $plex_info->{ name }, $plate->{ name }, $sample, );
                            print "Sample: ", $sample_name, "\n" if $options{verbose};
                            warn "Sample: ", $sample_name, "\n" if $options{debug};
                            
                            # open bam file. Use indices to generate file names if they exist.
                            my $name;
                            if( @indices ){
                                $name = $plex_info->{run_id} . '_' . $plex_info->{lane} . '#' . $indices[$i];
                            }
                            else{
                                $name = $sample_name;
                            }
                            
                            my $infile = File::Spec->catfile( $options{sample_directory}, $name . '.bam' );
                            
                            my $bam = Bio::DB::Sam->new(
                                -bam  => $infile,
                                -fasta => $options{reference},
                                -autoindex => 1,
                                -expand_flags => 1,
                            );
                            foreach my $region_hash ( @{ $plex->{region_info} } ){
                                print "Region: ", $region_hash->{region}, "\n" if $options{verbose};
                                warn "Region: ", $region_hash->{region}, "\n" if $options{debug};
                                my $region = $region_hash->{region};
                                
                                my %feature_args = (
                                    -iterator => 1,
                                    -type => 'match',
                                );
                                ( $feature_args{-seq_id}, $feature_args{-start}, $feature_args{-end} ) =
                                    split /[:-]/, $region;
                                
                                my ( $results_hash, $outliers_hash );
                                my $bam_iterator = $bam->features( %feature_args, );
                                while (my $align = $bam_iterator->next_seq){
                                    $results_hash->{read_count}++;
                                    # remove reads that don't have an INDEL
                                    my $cigar_string = $align->cigar_array;
                                    my $indel = 0;
                                    foreach my $cigar ( @{$cigar_string} ){
                                        if( $cigar->[0] =~ m/[DI]/xms ){
                                            $indel = 1;
                                        }
                                    }
                                    if( !$indel ){
                                        $results_hash->{wt_read_count}++;
                                        next;
                                    }
                                    
                                    warn join("\t", $align->start, $align->end, $align->dna,
                                            $align->cigar_str, $align->aux, 
                                            $align->query->start, $align->query->end, $align->query->dna, ), "\n" if $options{debug} > 2;
                                    
                                    # work out where deletion starts and ends and whether it overlaps a crispr site
                                    my ( $chr, $pos, $end, $ref, $alt, ) = parse_cigar_string( $align );
                                    find_overlapping_crisprs_and_add_to_hash( $align, $chr, $pos, $end, $ref, $alt, $results_hash, $outliers_hash, );
                                }
                                $results->{ $plate->{name} }{ $sample_name }{ $region } = $results_hash;
                                $outliers->{ $plate->{name} }{ $sample_name }{ $region } = $outliers_hash;
                                
                            }
                            # increment counter
                            $i++;
                        }
                    }
                }
            }
            # store CIGAR data for retrieval if scripts fails from this point
            my $data_object = {
                results => $results,
                outliers => $outliers,
                variants_seen => \%variants_seen,
            };
            
            my $return_value;
            eval {
                $return_value = store $data_object, $cigar_filename;
            };
            if( !$return_value ){
                warn "There was a problem storing the CIGAR results to disk. Continuing...\n";
            }
            if( $EVAL_ERROR ){
                warn "There was a problem storing the CIGAR results to disk. Continuing...\n",
                    $EVAL_ERROR, "\n";
            }
        }
        else{
            $results = $data_object->{results};
            $outliers = $data_object->{outliers};
            %variants_seen = %{ $data_object->{variants_seen} };
        }
        
        warn Dumper( $results, $outliers, ) if( $options{debug} > 1 );
        
        if( $options{no_pindel} ){
            warn "Option no_pindel specified. Skipping Pindel...\n";
        }
        else{
            # if pindel output doesn't exist, run pindel.
            print "Checking pindel data...\n" if $options{verbose};
            
            my %no_pindel_data;
            # if pindel directory exists, check for data
            set_up_directories( $options{pindel_directory}, );
            
            foreach my $plate ( @{ $plex_info->{plates} } ){
                foreach my $well_block ( @{ $plate->{wells} } ){
                    foreach my $plex ( @{ $well_block->{plexes} } ){
                        my $plex_output_dir = File::Spec->catfile($options{pindel_directory}, 'output', $plex->{name} );
                        my $plex_output_prefix = File::Spec->catfile($options{pindel_directory}, 'output', $plex->{name}, $plex->{name} );        
                        # check for the output directory and pindel output files
                        if( ! check_output_files( $plex, $plex_output_dir, $plex_output_prefix, \%no_pindel_data, ) ){
                            set_up_directories( $options{pindel_directory}, $plex, );
                            set_up_config_files( $plate, $well_block, $plex, );
                            run_pindel( $plex, \%no_pindel_data, );
                        }
                    }
                }
            }
            
            # go through pindel variants
            print "Checking pindel variants...\n" if $options{verbose};
            
            foreach my $plate ( @{ $plex_info->{plates} } ){
                foreach my $well_block ( @{ $plate->{wells} } ){
                    foreach my $plex ( @{ $well_block->{plexes} } ){
                        # check whether pindel data exists
                        next if( exists $no_pindel_data{ $plex->{name} } );
                        foreach my $region_hash ( @{ $plex->{region_info} } ){
                            my $region = $region_hash->{region};
                            # open vcf file for region
                            my $vcf_file = File::Spec->catfile(
                                $options{pindel_directory},
                                'output',
                                $plex->{name},
                                $plex->{name} . '.vcf.gz' );
                            # need to check for the existence of the concatenated vcf.gz file
                            if( ! -e $vcf_file ){
                                die "The expected pindel vcf file, $vcf_file, does not exist!\n";
                            }
                            else{
                                parse_vcf_file_for_region( $vcf_file, $plate, $region, $results, $outliers, );
                            }
                        }
                    }
                }
            }
            warn Dumper( $results, $outliers, %variants_seen, ) if( $options{debug} > 1 );
            
            # store cigar + pindel data for retrieval if scripts fails from this point
            my $data_object = {
                results => $results,
                outliers => $outliers,
                variants_seen => \%variants_seen,
            };
            
            my $return_value;
            eval {
                $return_value = store $data_object, $cigar_pindel_results_filename;
            };
            if( !$return_value ){
                warn "There was a problem storing the combined results to disk. Continuing...\n";
            }
            if( $EVAL_ERROR ){
                warn "There was a problem storing the combined results to disk. Continuing...\n",
                    $EVAL_ERROR, "\n";
            }
        }
    }
    else{
        $results = $data_object->{results};
        $outliers = $data_object->{outliers};
        %variants_seen = %{ $data_object->{variants_seen} };
    }

    # build up consensus sequence for top variants
    # also output alignments to bam file
    foreach my $plate ( @{ $plex_info->{plates} } ){
        foreach my $well_block ( @{ $plate->{wells} } ){
            foreach my $plex ( @{ $well_block->{plexes} } ){
                # counter
                my $i = 0;
                my @indices;
                # check for indices in the YAML hash. 
                if( exists $well_block->{indices} ){
                    @indices = split /,/, $well_block->{indices};
                }
                foreach my $sample ( @{ $well_block->{sample_names} } ){
                    my $sample_name = join("_", $plex_info->{ name }, $plate->{ name }, $sample, );
                    print $sample_name, "\n" if( $options{verbose} );
                    warn $sample_name, "\n" if( $options{debug} );
                    # open bam file. Use indices to generate file names if they exist.
                    my $name;
                    if( @indices ){
                        $name = $plex_info->{run_id} . '_' . $plex_info->{lane} . '#' . $indices[$i];
                    }
                    else{
                        $name = $sample_name;
                    }
                    
                    my $infile = File::Spec->catfile( $options{sample_directory}, $name . '.bam' );
                    print $infile, "\n" if $options{verbose};
                    
                    my $bam = Bio::DB::Sam->new(
                        -bam  => $infile,
                        -fasta => $options{reference},
                        -autoindex => 1,
                        -expand_flags => 1,
                    );
                    foreach my $region_hash ( @{ $plex->{region_info} } ){
                        my $region = $region_hash->{region};
                        my $results_hash = $results->{ $plate->{name} }{ $sample_name }{ $region };
                        next if( !exists $results_hash->{read_count} || $results_hash->{read_count} == 0 );
                        
                        my ( $chr, $start, $end, ) = split /[:-]/, $region;
                        # remove strand
                        $region =~ s/:\-?1 \z//xms; # match colon, 0 or 1 hyphens and a number 1 at the end of the region.
                        print $region, "\n" if( $options{verbose} );
                        warn $region, "\n" if( $options{debug} );
                        my %feature_args = (
                            -iterator => 1,
                            -type => 'match',
                            -seq_id => $chr,
                            -start => $start,
                            -end => $end,
                        );
                        
                        my %read_names; # READ_NAMES => VARIANT => READ_NAME => 1;
                        foreach my $crispr_name ( keys %{ $results_hash->{indels} } ){
                            print $crispr_name, "\n" if( $options{verbose} );
                            warn $crispr_name, "\n" if( $options{debug} );
                            #my @variants = grep {
                            #                        $results_hash->{indels}->{$crispr_name}->{$_}->{count}/$results_hash->{read_count} > $options{pc_filter}
                            #                    }   keys %{ $results_hash->{indels}->{$crispr_name} };
                            # Remove variants that are below threshold
                            my @variants;
                            foreach my $variant ( keys %{ $results_hash->{indels}->{$crispr_name} } ){
                                if( $results_hash->{indels}->{$crispr_name}->{$variant}->{count} < $COVERAGE_FILTER ){
                                    delete $results_hash->{indels}->{$crispr_name}->{$variant};
                                }
                                elsif( $results_hash->{indels}->{$crispr_name}->{$variant}->{count}/$results_hash->{read_count} < $options{pc_filter} ){
                                    delete $results_hash->{indels}->{$crispr_name}->{$variant};
                                }
                                else{
                                    push @variants, $variant;
                                }
                            }
                            
                            if( @variants ){
                                my %variants = map { $_ => 1, } @variants;
                                
                                my $bam_iterator = $bam->features( %feature_args, );
                                while (my $align = $bam_iterator->next_seq){
                                    my $cigar_string = $align->cigar_array;
                                    my $indel = 0;
                                    foreach my $cigar ( @{$cigar_string} ){
                                        if( $cigar->[0] =~ m/[DI]/xms ){
                                            $indel = 1;
                                        }
                                    }
                                    next if !$indel;
                                    
                                    warn join("\t", $align->start, $align->end, $align->dna,
                                            $align->cigar_str, $align->aux, 
                                            $align->query->start, $align->query->end, $align->query->dna, ), "\n" if $options{debug} > 2;
                                    
                                    # work out where indel starts and ends
                                    my ( $chr, $pos, $end, $ref, $alt, ) = parse_cigar_string( $align );
                                    my $variant = join(":", $chr, $pos, $ref, $alt, );
                                    if( exists $variants{ $variant } ){
                                        # add sequence to consensus
                                        $results_hash = add_sequence_to_consensus(
                                                            {
                                                                align => $align,
                                                                chr => $chr,
                                                                pos => $pos,
                                                                ref => $ref,
                                                                alt => $alt,
                                                                results => $results_hash,
                                                                crispr_name => $crispr_name,
                                                            },
                                                        );
                                        # add read name to read_names hash
                                        if( $results_hash->{indels}->{$crispr_name}->{$variant}->{count} > $DOWNSAMPLE_LIMIT ){
                                            my $fraction = $DOWNSAMPLE_LIMIT / $results_hash->{indels}->{$crispr_name}->{$variant}->{count};
                                            if( rand() < $fraction ){
                                                $read_names{ $variant }{ $align->query->name } = 1;
                                            }
                                        } else {
                                            $read_names{ $variant }{ $align->query->name } = 1;
                                        }
                                    }
                                }
                            }
                        }
                        
                        warn Dumper( %read_names ) if $options{debug} > 1;
                        
                        # open bam file and get header
                        my $in_bam = Bio::DB::Bam->open($infile, "r");
                        my $header = $in_bam->header();
                        
                        # open output bam file for each variant and write header
                        my %bam_fhs;
                        my $var_num = 1;
                        foreach my $variant ( keys %read_names ){
                            my $outfile = File::Spec->catfile( $options{output_directory}, 'bams', join(".", $name, $var_num, 'bam' ) );
                            my $out_bam = Bio::DB::Bam->open($outfile, "w");
                            $out_bam->header_write( $header );
                            $bam_fhs{ $variant } = $out_bam;
                            # add number for var to results hash
                            foreach my $crispr_name ( keys %{ $results_hash->{indels} } ){
                                if( exists $results_hash->{indels}->{$crispr_name}->{$variant} ){
                                    $results_hash->{indels}->{$crispr_name}->{$variant}->{var_num} = $var_num;
                                }
                                warn Dumper( $results_hash->{indels}->{$crispr_name}->{$variant} ) if $options{debug} > 1;
                            }
                            $var_num++;
                        }
                        
                        # open bai index and go through region
                        my $index = Bio::DB::Bam->index_open($infile);
                        my ( $tid, $r_start, $r_end, ) = $header->parse_region( $region );
                        
                        my $callback = sub {
                            my ( $alignment, $data, ) = @_;
                            my ( $bam, $read_names, $bam_fhs, ) = @{$data};
                            # write read to output bam file if the read name exists in the hash
                            foreach my $variant ( keys %{$read_names} ){
                                if( exists $read_names->{ $variant}{ $alignment->qname } ){
                                    $bam_fhs->{ $variant }->write1($alignment);
                                }
                            }
                        };
                        
                        my $code = $index->fetch($in_bam,$tid,$r_start,$r_end,$callback, [ $bam, \%read_names, \%bam_fhs, ] );
                    }
                    # increment counter
                    $i++;
                }
            }
        }
    }
    
    # index bam files with samtools
    opendir(my $bam_dir_fh, $output_bam_dir);
    foreach my $file (readdir($bam_dir_fh)) {
        next if( $file !~ m/bam \z/xms );
        my $bam_file = File::Spec->catfile( $output_bam_dir, $file, );
        warn $bam_file, "\n" if $options{debug};
        my $cmd = qq{ samtools index $bam_file };
        system( $cmd ) == 0 or die "system $cmd failed: $?";
    }
    
    warn Dumper( $results ) if $options{debug} > 1;
    
    # store combined data for retrieval if scripts fails from this point
    $data_object = {
        results => $results,
        outliers => $outliers,
        variants_seen => \%variants_seen,
    };
    
    my $return_value;
    eval {
        $return_value = store $data_object, $combined_results_filename;
    };
    if( !$return_value ){
        warn "There was a problem storing the combined results to disk. Continuing...\n";
    }
    if( $EVAL_ERROR ){
        warn "There was a problem storing the combined results to disk. Continuing...\n",
            $EVAL_ERROR, "\n";
    }

}
else{
    $results = $data_object->{results};
    $outliers = $data_object->{outliers};
    %variants_seen = %{ $data_object->{variants_seen} };
}

# run dindel on bams dir
if( !$options{no_dindel} ){
    run_dindel();
}

# print out results to txt file and vcf file
$out_fh->autoflush( 0 );
foreach my $plate ( @{ $plex_info->{plates} } ){
    foreach my $well_block ( @{ $plate->{wells} } ){
        foreach my $plex ( @{ $well_block->{plexes} } ){
            my $vcf_file = File::Spec->catfile( $options{output_directory},
                join(".", $plex->{name}, 'vcf', ) );
            open my $vcf_fh, '>', $vcf_file;
            my ( $samples, $index_for, ) = output_vcf_header_for_subplex( $vcf_fh, $plex, $well_block, );
            # make a new hash to store the data for the vcf file
            my %vcf_info; # VAR => { CHR, POS, REF, ALT, AD, GT } 
            # look up hash for each combination of sample and variant to avoid double counting due to multiple crisprs
            my %var_seen;
            
            my $sample_counter = 0;
            my @well_ids = @{ $well_block->{well_ids} };
            my $well_ids = join(",", @{ $well_block->{well_ids} } );
            foreach my $sample ( @{ $well_block->{sample_names} } ){
                my $sample_name = join("_", $plex_info->{ name }, $plate->{ name }, $sample, );
                foreach my $region_hash ( @{ $plex->{region_info} } ){
                    my $region = $region_hash->{region};
                    my $gene_name = $region_hash->{gene_name};
                    my $results_hash = $results->{ $plate->{name} }{ $sample_name }{ $region };
                    my $no_indels = 1;
                    
                    if( !keys %{ $results_hash->{indels} } ){
                        # print zeros for each crispr in the region
                        foreach my $crispr ( @{$region_hash->{crisprs}} ){
                            print {$out_fh} join("\t",
                                                $plex_info->{name},
                                                $plate->{name},
                                                $plex->{name},
                                                $well_ids[$sample_counter],
                                                $sample_name,
                                                $gene_name,
                                                $groups_for_crisprs{ $plate->{name} }{ $well_ids }{$crispr->name},
                                                $region,
                                                'NA', 'NA',
                                                $crispr->name,
                                                'NA', 'NA', 'NA', 'NA',
                                                0, $results_hash->{read_count} || 0, 0,
                                                'NA', 'NA', 'NA', ), "\n";
                        }
                    }
                    # otherwise print the counts and percentages
                    else{
                        foreach my $crispr ( @{$region_hash->{crisprs}} ){
                            my $crispr_name = $crispr->name;
                            my $no_indels = 1;
                            if ( scalar keys %{ $results_hash->{indels}->{$crispr_name} } ){
                                foreach my $variant ( keys %{ $results_hash->{indels}->{$crispr_name} } ){
                                    my ( $chr, $pos, $ref, $alt ) = split /:/, $variant;
                                    if( !exists $vcf_info{ $variant } ){
                                        $vcf_info{ $variant } = {
                                            chr => $chr,
                                            pos => $pos,
                                            ref => $ref,
                                            alt => $alt,
                                            AD => [  ],
                                            GT => [  ],
                                        };
                                    }
                                    # check var seen hash to avoid double counting
                                    if( !exists $var_seen{ $samples->[$sample_counter] . $variant } ){
                                        warn join(":", "Count", $results_hash->{indels}->{$crispr_name}->{$variant}->{count}, ), "\n",
                                            join(":", "WT count", ($results_hash->{wt_read_count} || '0' ), ), "\n";
                                        $vcf_info{$variant}->{total_counts} +=
                                            $results_hash->{indels}->{$crispr_name}->{$variant}->{count} +
                                                ($results_hash->{wt_read_count} || 0);
                                        $vcf_info{$variant}->{GT}->[ $index_for->{ $samples->[$sample_counter] } ] = '0/1';
                                        $vcf_info{$variant}->{AD}->[ $index_for->{ $samples->[$sample_counter] } ] =
                                            join(q{,},
                                                $results_hash->{indels}->{$crispr_name}->{$variant}->{count},
                                                ($results_hash->{wt_read_count} || '0'),
                                            );
                                        $var_seen{ $samples->[$sample_counter] . $variant } = 1;
                                    }
                                    
                                    my @line = ( $plex_info->{name},
                                                $plate->{name},
                                                $plex->{name},
                                                $well_ids[$sample_counter],
                                                $sample_name,
                                                $gene_name,
                                                $groups_for_crisprs{ $plate->{name} }{ $well_ids }{$crispr_name},
                                                $region,
                                                $results_hash->{indels}->{$crispr_name}->{ $variant }->{caller},
                                                $results_hash->{indels}->{$crispr_name}->{ $variant }->{overlap},
                                                $crispr_name,
                                                (split /:/, $variant),
                                                $results_hash->{indels}->{$crispr_name}->{$variant}->{count},
                                                $results_hash->{read_count},
                                                $results_hash->{indels}->{$crispr_name}->{$variant}->{count}/$results_hash->{read_count}, );
                                    if( exists $results_hash->{indels}->{$crispr_name}->{ $variant }->{consensus} ){
                                        my $consensus = create_consensus( $results_hash->{indels}->{$crispr_name}->{ $variant } );
                                        #print join("\n", $consensus, $options{consensus_filter} ), "\n" if $options{debug};
                                        if( length($consensus) < $options{consensus_filter} ){
                                            next;
                                        }
                                        push @line, ( $results_hash->{indels}->{$crispr_name}->{ $variant }->{consensus_start} - 1, 
                                                        $results_hash->{indels}->{$crispr_name}->{ $variant }->{ref_seq},
                                                        $consensus, );
                                    }
                                    else{
                                        push @line, 'NA', 'NA', 'NA';
                                    }
                                    
                                    print {$out_fh} join("\t", @line, ), "\n";
                                    $no_indels = 0;
                                }
                            }
                            
                            if( $no_indels ){
                                # If there are no indels above threshold for this sample and region and crispr print zeros
                                print {$out_fh} join("\t",
                                                    $plex_info->{name},
                                                    $plate->{name},
                                                    $plex->{name},
                                                    $well_ids[$sample_counter],
                                                    $sample_name,
                                                    $gene_name,
                                                    $groups_for_crisprs{ $plate->{name} }{ $well_ids }{$crispr_name},
                                                    $region,
                                                    'NA', 'NA',
                                                    $crispr_name,
                                                    'NA', 'NA', 'NA', 'NA',
                                                    0, $results_hash->{read_count} || 0, 0,
                                                    'NA', 'NA', 'NA', ), "\n";
                            }
                        }
                    }
                    
                    
                    my $outliers_hash = $outliers->{ $plate->{name} }{ $sample_name }{ $region };
                    # If there are indels for this sample print them
                    if( defined $outliers_hash ){
                        foreach my $variant ( keys %{ $outliers_hash->{indels} } ){
                            if( $outliers_hash->{indels}->{$variant}->{count}/$results_hash->{read_count} > $options{pc_filter} ){
                                print {$out_fh} join("\t", $plex_info->{name},
                                            $plate->{name},
                                            $plex->{name},
                                            $well_ids[$sample_counter],
                                            $sample_name,
                                            $gene_name,
                                            'NA',
                                            $region,
                                            $outliers_hash->{indels}->{ $variant }->{caller},
                                            $outliers_hash->{indels}->{ $variant }->{overlap},
                                            $outliers_hash->{indels}->{ $variant }->{crisprs},
                                            (split /:/, $variant),
                                            $outliers_hash->{indels}->{$variant}->{count},
                                            $results_hash->{read_count},
                                            $outliers_hash->{indels}->{$variant}->{count}/$results_hash->{read_count},
                                            'NA', 'NA', 'NA', ), "\n";
                            }
                        }
                    }
                }
                
                $sample_counter++; # increment well ids counter
            }
            # print info to vcf
            foreach my $var ( sort { $vcf_info{$a}->{chr} cmp $vcf_info{$b}->{chr} ||
                                        $vcf_info{$a}->{pos} <=> $vcf_info{$b}->{pos} } keys %vcf_info ){
                my $info = join(";",
                    join("=", 'DP', $vcf_info{$var}->{total_counts} ),
                );
                my $format_field = 'GT:AD';
                my @vcf_line = ( $vcf_info{$var}->{chr}, $vcf_info{$var}->{pos},
                    ".", $vcf_info{$var}->{ref}, $vcf_info{$var}->{alt},
                    ".", "PASS", $info, $format_field,
                );
                
                foreach ( my $index = 0; $index < scalar @{$samples}; $index++ ){
                    push @vcf_line, join(":",
                        $vcf_info{$var}->{GT}[$index] || './.',
                        $vcf_info{$var}->{AD}[$index] || '.',
                    );
                }
                print $vcf_fh join("\t", @vcf_line, ), "\n";
            }
        }
    }
}

sub set_up_directories {
    my ( $pindel_dir, $plex, ) = @_;
    
    my $config_dir = File::Spec->catfile($pindel_dir, 'config' );
    my $output_dir = File::Spec->catfile($pindel_dir, 'output' );
    
    # check if they exist first
    my @dir_to_create;
    foreach my $dir ( $pindel_dir, $config_dir, $output_dir ){
        if( !-e $dir ){
            push @dir_to_create, $dir;
        }
    }
    if( @dir_to_create ){
        my @created_dirs = make_path( @dir_to_create );
        if( scalar @created_dirs != scalar @dir_to_create ){
            die "Could not create pindel directories, ",
                join("\t", @created_dirs ), "!\n";
        }
    }
    
    if( $plex ){
        my $plex_output_dir = File::Spec->catfile( $output_dir, $plex->{name} );
        if( !-e $plex_output_dir ){
            if( ! scalar make_path( $plex_output_dir ) ){
                die "Could not create pindel subplex output directory, $plex_output_dir!\n";
            }
        }
    }
    
}

sub check_output_files {
    my ( $plex, $plex_output_dir, $plex_output_prefix, $no_pindel_data, ) = @_;
    my $pindel_out = 0;
    my $vcfs = 1;
    if( ! -e $plex_output_dir ){
        return 0;
    }
    else{
        # check for vcf files
        foreach my $type ( @TYPES ){
            my $pindel_vcf_file = join("_", $plex_output_prefix, $type ) . '.vcf';
            if( ! -e $pindel_vcf_file ){
                $vcfs = 0;
            }
        }
        if( !$vcfs ){
            # check whether the pindel output files exist
            foreach my $type ( @TYPES ){
                my $pindel_file = join("_", $plex_output_prefix, $type );
                if( -e $pindel_file && -s $pindel_file ){
                    $pindel_out = 1;
                }
            }
            if( !$vcfs && $pindel_out ){
                # run pindel_to_vcf
                pindel_to_vcf( $plex, $plex_output_prefix, $no_pindel_data, );
                $vcfs = 1;
            }
        }
    }
    
    if( $vcfs ){
        my $vcf_file = File::Spec->catfile(
            $options{pindel_directory},
            'output',
            $plex->{name},
            $plex->{name} . '.vcf.gz' );
        if( ! -e $vcf_file ){
            concat_vcfs( $plex, $plex_output_prefix, );
        }
        return 1;
    }
    
    return 0;
}

sub set_up_config_files {
    my ( $plate, $well_block, $plex, ) = @_;
    
    
    my $config_dir = File::Spec->catfile( $options{pindel_directory}, 'config' );

    my $regions_bed_file = File::Spec->catfile( $config_dir, $plex->{name} . '-regions.bed' );
    
    my @insert_sizes;
    if( !-e $regions_bed_file ){
        open my $regions_fh, '>', $regions_bed_file;
        
        foreach my $region_hash ( @{ $plex->{region_info} } ){
            my ( $chr, $start, $end, ) = split /[:-]/, $region_hash->{region};
            $start--;
            push @insert_sizes, $end - $start;
            # open output file
            print {$regions_fh} join("\t", $chr, $start, $end, $region_hash->{gene_name}, ), "\n";
        }
        close( $regions_fh );
    }
    
    my $pindel_config_file = File::Spec->catfile(
                $config_dir,
                $plex->{name} . '.txt' );
    
    if( !-e $pindel_config_file ){
        open my $pindel_config_fh, '>', $pindel_config_file;
        
        # counter
        my $i = 0;
        my @indices;
        # check for indices in the YAML hash. 
        if( exists $well_block->{indices} ){
            @indices = split /,/, $well_block->{indices};
        }
        foreach my $sample ( @{ $well_block->{sample_names} } ){
            my $sample_name = join("_", $plex_info->{ name }, $plate->{ name }, $sample, );
            
            # construct bam file name. Use indices to generate file names if they exist.
            my $name;
            if( @indices ){
                $name = $plex_info->{run_id} . '_' . $plex_info->{lane} . '#' . $indices[$i] . '.trimmed.filtered';
            }
            else{
                $name = $sample_name;
            }
            
            my $bam_file = File::Spec->catfile( $options{sample_directory}, $name . '.bam' );
            my $mean_insert_size = int( sum( @insert_sizes )/ scalar( @insert_sizes ) );
            print {$pindel_config_fh} join("\t", $bam_file, sprintf("%d", $mean_insert_size, ), $sample_name, ), "\n";
        }
        
        close( $pindel_config_fh );
    }
    #return

}

sub run_pindel {
    my ( $plex, $no_pindel_data, ) = @_;
    
    print "Running pindel...\n" if $options{verbose};

    my $pindel_bin = File::Spec->catfile( $options{pindel_path}, 'pindel' );
    
    # run pindel for this plex
    print "Pindel: ", $plex->{name}, "\n" if $options{verbose};
    #my $plex_output_dir = File::Spec->catfile($options{pindel_directory}, 'output', $plex->{name} );
    #my @created_dirs = make_path( $plex_output_dir );
    my $plex_output_prefix = File::Spec->catfile($options{pindel_directory}, 'output', $plex->{name}, $plex->{name} );
    my $pindel_config_file = File::Spec->catfile(
        $options{pindel_directory},
        'config',
        $plex->{name} . '.txt' );
    my $regions_bed_file = File::Spec->catfile(
        $options{pindel_directory},
        'config',
        $plex->{name} . '-regions.bed' );
    my $cmd = join(q{ }, $pindel_bin,
                   '-f', $options{reference},
                   '-i', $pindel_config_file,
                   '--include', $regions_bed_file,
                   '-o', $plex_output_prefix, );
    
    print $cmd, "\n" if $options{debug} > 1;
    ##  RUN PINDEL  ##
    eval { system( $cmd ); };
    if( $EVAL_ERROR && $EVAL_ERROR =~ m/unexpectedly\sreturned\sexit\svalue/xms ){
        warn "WARNING: PINDEL FAILED FOR SUBPLEX ", $plex->{name}, "!\n",
            "ERROR MESSAGE: ", $EVAL_ERROR, "\n";
        $no_pindel_data->{ $plex->{name} } = 1;
    }
    elsif( $EVAL_ERROR ){
        die $EVAL_ERROR;
    }
    else{
        # run pindel_to_vcf
        pindel_to_vcf( $plex, $plex_output_prefix, $no_pindel_data, );
        
        # concat vcfs
        concat_vcfs( $plex, $plex_output_prefix, );
    }
}

sub pindel_to_vcf {
    my ( $plex, $plex_output_prefix, $no_pindel_data, ) = @_;
    
    my $pindel2vcf = File::Spec->catfile( $options{pindel_path}, 'pindel2vcf' );
    
    foreach my $type ( @TYPES ){
        my $pindel_file = join("_", $plex_output_prefix, $type );
        my $cmd = join(q{ }, $pindel2vcf,
                       '-r', $options{reference},
                       '-R', $options{assembly},
                       '-d', $todays_date,
                       '-p', $pindel_file, );
        
        print $cmd, "\n" if $options{debug} > 1;
        eval { system( $cmd ); };
        if( $EVAL_ERROR && $EVAL_ERROR =~ m/unexpectedly\sreturned\sexit\svalue/xms ){
            $no_pindel_data->{ $plex->{name} } = 1;
        }
        elsif( $EVAL_ERROR ){
            die $EVAL_ERROR;
        }
    }
}

sub concat_vcfs {
    my ( $plex, $plex_output_prefix, ) = @_;
    
    # concatenate vcf files and index
    # first get a list of files to concat
    my @files_to_concat;
    foreach my $type ( @TYPES ){
        my $pindel_vcf_file = join("_", $plex_output_prefix, $type ) . '.vcf';
        open my $vcf_fh, '<', $pindel_vcf_file;
        while( my $line = <$vcf_fh> ){
            next if( $line !~ m/^\#CHROM/xms );
            chomp $line;
            my @columns = split /\t/, $line;
            # could also check that numbers of columns match each other
            if( @columns > 8 ){
                push @files_to_concat, $pindel_vcf_file;
            }
        }
        close( $vcf_fh );
    }
    
    my $vcf_file = File::Spec->catfile(
        $options{pindel_directory},
        'output',
        $plex->{name},
        $plex->{name} . '.vcf.gz' );
    
    if( @files_to_concat ){
        
        my $concat_cmd = join(q{ }, $options{vcfconcat}, @files_to_concat, q{|},
                              $options{vcfsort}, q{|}, 
                              qq{bgzip -c > $vcf_file} );
        eval{ system( $concat_cmd ) };
        if( $EVAL_ERROR ){
            die $EVAL_ERROR;
        }
        my $tabix_cmd = qq{tabix $vcf_file};
        eval{ system( $tabix_cmd ) };
        if( $EVAL_ERROR ){
            die $EVAL_ERROR;
        }
    }
    else{
        open my $vcf_fh, '>', $vcf_file;
        close( $vcf_fh );
    }
    #return
}

sub parse_vcf_file_for_region {
    my ( $vcf_file, $plate, $region, $results, $outliers, ) = @_;
    
    my @samples;
    my $tabix_cmd = qq{ tabix -h $vcf_file $region 2>&1 };
    open my $vcf_pipe, '-|', $tabix_cmd;
    my $error_message = '[tabix] the index file either does not exist or is older than the vcf file. Please reindex';
    my $err_regex = qr/$error_message/;
    
    while ( my $line = <$vcf_pipe>) {
        chomp $line;
        if( $line =~ m/$err_regex/xms ){
            die $error_message, "\n", $vcf_file, "\n";
        }
        elsif( $line =~ m/\[tabix]/xms ){
            warn $line, "\n", $vcf_file, "\n";
            next;
        }
        elsif( $line =~ m/\A \#\# /xms ){
            next;
        }
        elsif( $line =~ m/\A \#CHROM /xms ){
            @samples = get_sample_columns_from_line( $line );
            next;
        }
        else{
            my ($chr, $pos, undef, $ref, $alt, undef, undef, $info, $format, @fields) = split /\t/xms, $line;
            
            # skip variants already seen in CIGAR strings
            my $variant = join(":", $chr, $pos, $ref, $alt );
            if( exists $variants_seen{ $variant } ){
                warn "Variant ", $variant, " discarded because it has been seen before!\n";
                next;
            }
            
            # parse info field for end of the variant
            my %info = map { my ( $k, $v ) = split /=/, $_;
                                $k => $v; } split /;/, $info;
            warn Dumper( %info ) if( $options{debug} > 2 );
            
            # check whether this variant overlaps with a crispr
            my $overlapping_crisprs = $crispr_tree->fetch_overlapping_intervals( $chr, $pos - $INTERVAL_EXTENDER, $info{END} + $INTERVAL_EXTENDER );
            my $overlap_type;
            my @crisprs;
            if( !@{$overlapping_crisprs} ){
                # check whether it is inside the crispr pair
                my $overlapping_pairs = $crispr_pair_tree->fetch_overlapping_intervals( $chr, $pos - $INTERVAL_EXTENDER, $info{END} + $INTERVAL_EXTENDER );
                if( !@{$overlapping_pairs} ){
                    $overlap_type = 'non-overlapping';
                }
                else{
                    $overlap_type = 'crispr_pair';
                    @crisprs = map { @{$_} } @{$overlapping_pairs};
                }
            }
            else{
                @crisprs = @{$overlapping_crisprs};
                $overlap_type = scalar @crisprs == 2    ?   'crispr_pair'
                    :                                       'crispr';
            }
            
            my @types = split /:/xms, $format;
            my $type_index = 0;
            my %type = map { $_ => $type_index++ } @types;
            
            # go through samples
            my $i = 0;
            foreach my $field (@fields) {
                my @data = split /:/xms, $field;
                next if $data[$type{GT}] eq '.'; # no-call
                # get allele depths
                my @depths = split /,/, $data[$type{AD}];
                # check whether alt allele represented
                if( $depths[1] == 0 ){
                    $i++;
                    next;
                }
                
                # store variant in correct hash
                if( $overlap_type eq 'non-overlapping' ){
                    $outliers->{ $plate->{name} }{ $samples[$i] }{ $region }->{indels}->{ $variant }->{count} += $depths[1];
                    $outliers->{ $plate->{name} }{ $samples[$i] }{ $region }->{indels}->{ $variant }->{caller} = 'PINDEL';
                    $outliers->{ $plate->{name} }{ $samples[$i] }{ $region }->{indels}->{ $variant }->{overlap} = $overlap_type;
                    $outliers->{ $plate->{name} }{ $samples[$i] }{ $region }->{indels}->{ $variant }->{crisprs} = 'NA';
                }
                elsif( @crisprs ){
                    foreach my $crispr ( @crisprs ){
                        $results->{ $plate->{name} }{ $samples[$i] }{ $region }->{indels}->{$crispr->name}->{ $variant }->{count} += $depths[1];
                        $results->{ $plate->{name} }{ $samples[$i] }{ $region }->{indels}->{$crispr->name}->{ $variant }->{caller} = 'PINDEL';
                        $results->{ $plate->{name} }{ $samples[$i] }{ $region }->{indels}->{$crispr->name}->{ $variant }->{overlap} = $overlap_type;
                        $results->{ $plate->{name} }{ $samples[$i] }{ $region }->{indels}->{$crispr->name}->{ $variant }->{crisprs} = $crispr;
                    }
                }
                
                # increment sample counter
                $i++;
            }
        }
    }
}

sub get_sample_columns_from_line {
    my ($line) = @_;
    
    chomp $line;
    my @samples = split /\t/xms, $line;
    
    # Remove first nine columns that don't correspond to samples
    splice @samples, 0, 9;
    
    return @samples;
}

sub parse_cigar_string {
    my ( $align, $results_hash, $outliers_hash, ) = @_;
    
    my $chr = $align->seq_id;
    my $ref_gpos = $align->start - 1;
    my $ref_pos = 0; # 
    my $query_pos = $align->query->start - 1;
    my $end;
    my $ref_dna = $align->dna;
    my $query_dna = $align->query->dna;
    my $cigar_string = $align->cigar_str;
    if( $cigar_string =~ m/\A ([0-9]*[SH]*[0-9]+M)      # preceeding clipped and matching 
                            ([0-9]+[DI])                # deletion or insertion
                            ([0-9]+M)                   # match
                            ([0-9]+[DI])                # deletion or insertion
                            /xms ){
        
        my ( $ref_length, $alt_length ) = (0,0);
        my ( $prematch, $indel_1, $mid_match, $indel_2 ) = ( $1, $2, $3, $4 );
        $prematch =~ m/([0-9]+)M/xms;
        my $prematch_dist = $1;
        $query_pos += $prematch_dist;
        $ref_gpos += $prematch_dist;
        $ref_pos += $prematch_dist;
        $end = $ref_gpos;
        foreach ( $indel_1, $mid_match, $indel_2 ){
            m/([0-9]+)([DIM])/xms;
            my ( $num,  $type ) = ( $1,  $2 );
            if( $type eq 'D' ){
                $ref_length += $num;
                $end += $num;
            }
            elsif( $type eq 'I' ){
                $alt_length += $num;
            }
            else{
                $ref_length += $num;
                $end += $num;
                $alt_length += $num;
            }
        }
        my $ref = substr( $ref_dna, $ref_pos - 1, $ref_length + 1 );
        my $alt = substr( $query_dna, $query_pos - 1, $alt_length + 1 );
        
        warn join("\t", $ref_gpos, $ref_pos, $query_pos, $ref, $alt, ), "\n" if $options{debug} > 2;
        return ( $chr, $ref_gpos, $end, $ref, $alt, );
    }
    else{
        # split CIGAR string into blocks
        while( $cigar_string =~ m/([0-9]+)([SHMDI])/xmsg ){
            warn $1, ":", $2, "\n" if $options{debug} > 2;
            my ( $num,  $type ) = ( $1,  $2 );
            # if it's clipped, doesn't appear in the sequence. No need to advance counters.
            if( $type =~ m/[SH]/xms ){
                next;
            }
            elsif( $type =~ m/M/xms ){
                warn join("\t", $ref_gpos, $ref_pos, $query_pos, substr($ref_dna, $ref_pos, $num ), substr($query_dna, $query_pos, $num ), ), "\n" if $options{debug} > 2;
                $ref_gpos += $num;
                $query_pos += $num;
                $ref_pos += $num;
                warn join("\t", $ref_gpos, $ref_pos, $query_pos, ), "\n" if $options{debug} > 2;
            }
            elsif( $type eq 'D' ){
                warn join("\t", $ref_gpos, $ref_pos, $query_pos, substr($ref_dna, $ref_pos - 1, $num + 1 ), substr($query_dna, $query_pos - 1, $num + 1 ), ), "\n" if $options{debug} > 2;
                my $ref = substr( $ref_dna, $ref_pos - 1, $num + 1 );
                my $alt = substr($ref, 0, 1);
                $end = $ref_gpos + $num;
                # check whether there are potential mismatches
                my $mismatch_count = $align->get_tag_values( 'NM' );
                warn $mismatch_count if $options{debug} > 2;
                if( $mismatch_count > $num ){
                    # check next base for mismatch
                    $ref_pos += $num;
                    
                    my $ref_base = substr($ref_dna, $ref_pos, 1 );
                    my $query_base = substr($query_dna, $query_pos, 1 );
                    while( $ref_base ne $query_base ){
                        # add ref base to ref and query base to query
                        $ref .= $ref_base;
                        $alt .= $query_base;
                        $ref_pos++;
                        $query_pos++;
                        $ref_base = substr($ref_dna, $ref_pos, 1 );
                        $query_base = substr($query_dna, $query_pos, 1 );
                    }
                }
                
                warn join("\t", $ref_gpos, $ref_pos, $query_pos, $ref, $alt, ), "\n" if $options{debug} > 2;
                return ( $chr, $ref_gpos, $end, $ref, $alt, );
            }
            elsif( $type eq 'I' ){
                warn join("\t", $ref_gpos, $ref_pos, $query_pos, substr($ref_dna, $ref_pos - 1, $num + 1 ), substr($query_dna, $query_pos - 1, $num + 1 ), ), "\n" if $options{debug} > 2;
                my $alt = substr( $query_dna, $query_pos - 1, $num + 1 );
                my $ref = substr( $alt, 0, 1 );
                $end = $ref_gpos;
                warn join("\t", $ref_gpos, $ref_pos, $query_pos, $ref, $alt), "\n" if $options{debug} > 2;
                
                # check whether there are potential mismatches
                my $mismatch_count = $align->get_tag_values( 'NM' );
                warn $mismatch_count if $options{debug} > 2;
                if( $mismatch_count > $num ){
                    # check next base for mismatch
                    $query_pos += $num;
                    
                    my $ref_base = substr($ref_dna, $ref_pos, 1 );
                    my $query_base = substr($query_dna, $query_pos, 1 );
                    while( $ref_base ne $query_base ){
                        # add ref base to ref and query base to query
                        $ref .= $ref_base;
                        $alt .= $query_base;
                        $ref_pos++;
                        $query_pos++;
                        $ref_base = substr($ref_dna, $ref_pos, 1 );
                        $query_base = substr($query_dna, $query_pos, 1 );
                    }
                }
                return ( $chr, $ref_gpos, $end, $ref, $alt, );
            }
        }
    }
}

sub find_overlapping_crisprs_and_add_to_hash {
    my ( $align, $chr, $ref_gpos, $end, $ref, $alt, $results_hash, $outliers_hash ) = @_;
    
    my $variant = join(":", $chr, $ref_gpos, $ref, $alt );
    # sanity check on variant
    eval{
        check_variant( $ref, $alt );
    };
    if( $EVAL_ERROR && $EVAL_ERROR =~ m/Variant\sdoesn't\smake\ssense:/xms ){
        print_error( $align, $EVAL_ERROR, );
    }
    else{
        $variants_seen{ join(":", $chr, $ref_gpos, $ref, $alt ) } = 1;
    }
    
    # check if it overlaps a crispr
    my $overlapping_crisprs = $crispr_tree->fetch_overlapping_intervals( $align->seq_id, $ref_gpos - $INTERVAL_EXTENDER, $end + $INTERVAL_EXTENDER );
    my $overlap_type;
    my @crisprs;
    if( !@{$overlapping_crisprs} ){
        # check whether it is inside the crispr pair
        my $overlapping_pairs = $crispr_pair_tree->fetch_overlapping_intervals( $align->seq_id, $ref_gpos - $INTERVAL_EXTENDER, $end + $INTERVAL_EXTENDER );
        if( !@{$overlapping_pairs} ){
            $outliers_hash->{indels}->{ $variant }->{count}++;
            $outliers_hash->{indels}->{ $variant }->{caller} = 'CIGAR';
            $outliers_hash->{indels}->{ $variant }->{overlap} = 'non-overlapping';
            $outliers_hash->{indels}->{ $variant }->{crisprs} = 'NA';
        }
        else{
            $overlap_type = 'crispr_pair';
            @crisprs = map { @{$_} } @{$overlapping_pairs};
        }
    }
    else{
        @crisprs = @{$overlapping_crisprs};
        $overlap_type = scalar @crisprs == 2    ?   'crispr_pair'
            :                                       'crispr';
    }
    
    if( @crisprs ){
        foreach my $crispr ( @crisprs ){
            $results_hash->{indels}->{$crispr->name}->{ $variant }->{count}++;
            $results_hash->{indels}->{$crispr->name}->{ $variant }->{caller} = 'CIGAR';
            $results_hash->{indels}->{$crispr->name}->{ $variant }->{overlap} = $overlap_type;
            $results_hash->{indels}->{$crispr->name}->{ $variant }->{crisprs} = $crispr;
        }
    }
}

sub print_error {
    my ( $align, $EVAL_ERROR, ) = @_;
    warn $EVAL_ERROR, join("\t", $align->start, $align->end, $align->dna,
    $align->cigar_str, $align->aux, 
    $align->query->start, $align->query->end, $align->query->dna, ), "\n";
}

sub check_variant {
    my ( $ref, $alt ) = @_;
    if( $ref !~ m/\A [A-Z]+ \z/xms || $alt !~ m/\A [A-Z]+ \z/xms ){
        die "Variant doesn't make sense: \n";
    }
}

sub add_sequence_to_consensus {
    my ( $args, ) = @_;
    
    my $variant = join(":", $args->{chr}, $args->{pos}, $args->{ref}, $args->{alt}, );
    # check for consensus and set up new consensus if neccessary
    my $results_hash = $args->{results};
    my $align = $args->{align};
    if( !exists $results_hash->{indels}->{ $args->{crispr_name} }->{ $variant }->{consensus} ){
        $results_hash->{indels}->{ $args->{crispr_name} }->{ $variant }->{consensus_start} = $align->start - 150;
        $results_hash->{indels}->{ $args->{crispr_name} }->{ $variant }->{consensus} = [  ];
        $results_hash->{indels}->{ $args->{crispr_name} }->{ $variant }->{ref_seq} = $align->dna;
    }
    
    # go through sequence and add bases to consensus
    my $pos_index = $args->{align}->start - $results_hash->{indels}->{ $args->{crispr_name} }->{ $variant }->{consensus_start};
    if( $pos_index < 0 ){
        die "consensus is screwed up!\n";
    }
    # count up bases and move along the array
    foreach my $base ( split //, $align->query->dna ){
        $results_hash->{indels}->{ $args->{crispr_name} }->{ $variant }->{consensus}->[$pos_index]->{$base}++;
        $pos_index++;
    }
    return $results_hash;
}

sub create_consensus {
    my ( $results_for_variant, ) = @_;
    
    my %ambig_codes = (
        AC => 'M',
        AG => 'R',
        AT => 'W',
        CG => 'S',
        CT => 'Y',
        GT => 'K',
    );
    
    my $consensus = $results_for_variant->{consensus};
    my $consensus_seq;
    foreach my $pos ( 0 .. scalar @{$consensus} ){
        if( !defined $consensus->[$pos] ){
            $results_for_variant->{consensus_start}++;
            next;
        }
        
        my @bases = keys %{ $consensus->[$pos] }; 
        if( scalar @bases == 1 ){
            $consensus_seq .= $bases[0];
        }
        else{
            my @freqs = sort { $b <=> $a } values %{ $consensus->[$pos] };
            my @sorted_bases = sort { $consensus->[$pos]->{$b} <=> $consensus->[$pos]->{$a} } @bases;
            
            if( $freqs[0] > 2 * $freqs[1] ){
                $consensus_seq .= $sorted_bases[0];
            }
            else{
                # remove Ns
                my @filtered_bases;
                foreach ( my $i = 0; $i < scalar @sorted_bases; $i++ ){
                    if( $sorted_bases[$i] ne 'N' ){
                        push @filtered_bases, $sorted_bases[$i];
                    }
                }
                if( scalar @filtered_bases == 1 ){
                    $consensus_seq .= $filtered_bases[0];
                }
                else{
                    $consensus_seq .= $ambig_codes{ join(q{}, sort { $a cmp $b } @filtered_bases[0,1]) };                    
                }
            }
        }
    }
    return $consensus_seq;
}

sub run_dindel {
    # for each sample
    foreach my $plate ( @{ $plex_info->{plates} } ){
        foreach my $well_block ( @{ $plate->{wells} } ){
            foreach my $plex ( @{ $well_block->{plexes} } ){
                # counter
                my $i = 0;
                my @indices;
                # check for indices in the YAML hash. 
                if( exists $well_block->{indices} ){
                    @indices = split /,/, $well_block->{indices};
                }
                foreach my $sample ( @{ $well_block->{sample_names} } ){
                    my $sample_name = join("_", $plex_info->{ name }, $plate->{ name }, $sample, );
                    print $sample_name, "\n" if( $options{verbose} );
                    warn $sample_name, "\n" if( $options{debug} );
                    # open bam file. Use indices to generate file names if they exist.
                    my $name;
                    if( @indices ){
                        $name = $plex_info->{run_id} . '_' . $plex_info->{lane} . '#' . $indices[$i];
                    }
                    else{
                        $name = $sample_name;
                    }
                    
                    foreach my $region_hash ( @{ $plex->{region_info} } ){
                        my $region = $region_hash->{region};
                        my $results_hash = $results->{ $plate->{name} }{ $sample_name }{ $region };
                        next if( !exists $results_hash->{read_count} || $results_hash->{read_count} == 0 );
                        
                        # set up directories
                        my $var_nums_hash = set_up_dindel_directories( $name, $results_hash, );
                        
                        foreach my $var_num ( keys %{$var_nums_hash} ){
                            my $vcf_file;
                            # extract indels
                            my ( $selected_var_file, $lib_file ) = dindel_extract_indels( $name, $var_num, );
                            if( $selected_var_file ){
                                #make windows
                                my @window_files = dindel_make_windows( $name, $var_num, $selected_var_file, );
                                
                                #realign windows
                                my @glf_files = dindel_realign_windows( $name, $var_num, \@window_files, $lib_file );
                                
                                $vcf_file = dindel_make_vcf_file( $name, $var_num, \@glf_files, );
                                
                                # go through vcf_file and try to match it to one of the variants
                                # open vcf file
                                open my $vcf_fh, '<', $vcf_file;
                                while( my $line = <$vcf_fh> ){
                                    next if $line =~ /\A\#/xms;
                                    my ( $chr, $pos, undef, $ref, $alt, undef, ) = split /\t/, $line;
                                    my $vcf_var = join(":", $chr, $pos, $ref, $alt, );
                                    my $var_end = length($ref) > length($alt)   ?
                                            $pos + length($ref)
                                        :   $pos;
                                    
                                    # check whether this variant overlaps with a crispr
                                    my $overlapping_crisprs = $crispr_tree->fetch_overlapping_intervals( $chr, $pos - $INTERVAL_EXTENDER, $var_end + $INTERVAL_EXTENDER );
                                    my $overlap_type;
                                    my @crisprs;
                                    if( !@{$overlapping_crisprs} ){
                                        # check whether it is inside the crispr pair
                                        my $overlapping_pairs = $crispr_pair_tree->fetch_overlapping_intervals( $chr, $pos - $INTERVAL_EXTENDER, $var_end + $INTERVAL_EXTENDER );
                                        if( !@{$overlapping_pairs} ){
                                            $overlap_type = 'non-overlapping';
                                        }
                                        else{
                                            $overlap_type = 'crispr_pair';
                                            @crisprs = map { @{$_} } @{$overlapping_pairs};
                                        }
                                    }
                                    else{
                                        @crisprs = @{$overlapping_crisprs};
                                        $overlap_type = scalar @crisprs == 2    ?   'crispr_pair'
                                            :                                       'crispr';
                                    }
                                    next if( $overlap_type eq 'non-overlapping' );
                                    
                                    my $predicted_var = $var_nums_hash->{$var_num};
                                    if( $predicted_var ne $vcf_var ){
                                        foreach my $crispr_name ( map { $_->name } @crisprs ){
                                            if( exists $results_hash->{indels}->{$crispr_name}->{$vcf_var} ){
                                                # merge hashes and delete predicted var
                                                $results_hash->{indels}->{$crispr_name}->{$vcf_var}->{caller} = 'DINDEL';
                                                $results_hash->{indels}->{$crispr_name}->{$vcf_var}->{count} +=
                                                    $results_hash->{indels}->{$crispr_name}->{$predicted_var}->{count};
                                                
                                                # merge consensuses
                                                my $vcf_var_start = $results_hash->{indels}->{$crispr_name}->{$vcf_var}->{consensus_start};
                                                my $predicted_var_start = $results_hash->{indels}->{$crispr_name}->{$predicted_var}->{consensus_start};
                                                my $first_var = $vcf_var_start <= $predicted_var_start ? $vcf_var : $predicted_var;
                                                my $second_var = $vcf_var_start <= $predicted_var_start ? $predicted_var : $vcf_var;
                                                my $pos = $vcf_var_start <= $predicted_var_start ? $vcf_var_start : $predicted_var_start;
                                                $results_hash->{indels}->{$crispr_name}->{$vcf_var}->{consensus_start} = $pos;
                                                my @consensus;
                                                my $second_var_index = 0;
                                                foreach my $bases ( @{ $results_hash->{indels}->{$crispr_name}->{$first_var}->{consensus} } ){
                                                    if( $pos < $predicted_var_start ){
                                                        push @consensus, $bases;
                                                    }
                                                    else{
                                                        my $predicted_var_bases = $results_hash->{indels}->{$crispr_name}->{$second_var}->{consensus}->[$second_var_index];
                                                        if( !defined $bases && !defined $predicted_var_bases ){
                                                            push @consensus, undef;
                                                        }
                                                        elsif( !defined $predicted_var_bases ){
                                                            push @consensus, $bases;
                                                        }
                                                        else{
                                                            # merge the two hashes
                                                            my $merged_bases = $hash_merge_consensus->merge( $bases, $predicted_var_bases );
                                                            push @consensus, $merged_bases;
                                                        }
                                                        $second_var_index++;
                                                    }
                                                    $pos++;
                                                }
                                                
                                                warn "MERGED:\n", Dumper( $results_hash->{indels}->{$crispr_name}->{$vcf_var} ) if $options{debug} > 1;
                                                delete $results_hash->{indels}->{$crispr_name}->{$predicted_var};
                                            }
                                            else{
                                                # add vcf_var to hash and delete predicted var
                                                $results_hash->{indels}->{$crispr_name}->{$vcf_var} = $results_hash->{indels}->{$crispr_name}->{$predicted_var};
                                                delete $results_hash->{indels}->{$crispr_name}->{$predicted_var};
                                            }
                                        }
                                    }
                                    else{
                                        foreach my $crispr_name ( map { $_->name } @crisprs ){
                                            if( exists $results_hash->{indels}->{$crispr_name}->{$vcf_var} ){
                                                $results_hash->{indels}->{$crispr_name}->{$vcf_var}->{caller} = 'DINDEL';
                                            }
                                            else{
                                                # warn and output some diagnostic info
                                                warn join(q{ }, "SAMPLE:", $sample_name,
                                                    "VAR NUM:", $var_num,
                                                    "Variant from dindel vcf,", $vcf_var,
                                                    "matches CIGAR string variant,", $predicted_var . ',',
                                                    "but does not appear in the results hash!\n", );
                                                warn Dumper( $results_hash );
                                            }
                                        }
                                    }
                                    
                                }
                            }
                            else{
                                warn "No candidate variants for $sample_name, $region.\n";
                            }
                        }
                    }
                    # increment counter
                    $i++;
                }
            }
        }
    }
}

sub set_up_dindel_directories {
    my ( $name, $results_hash ) = @_;
    
    #check base indel directory
    my $dindel_dir = File::Spec->catfile( $options{output_directory}, 'dindel' );
    if( !-e $dindel_dir ){
        make_path( $dindel_dir );
    }
    my %var_nums;
    foreach my $crispr_name ( keys %{ $results_hash->{indels} } ){
        foreach my $variant ( keys %{ $results_hash->{indels}->{$crispr_name} } ){
            if( exists $results_hash->{indels}->{$crispr_name}->{$variant}->{var_num} ){
                $var_nums{ $results_hash->{indels}->{$crispr_name}->{$variant}->{var_num} } = $variant;
            }
        }
    }
    foreach my $var_num ( keys %var_nums ){
        foreach my $dir ( 'extract_indels', 'windows' ){
            my $sample_dir = File::Spec->catfile(
                $options{output_directory}, 'dindel',
                $name, join(q{.}, $name, $var_num, ), $dir );
            make_path( $sample_dir );
        }
    }
    return ( \%var_nums );
}

sub dindel_extract_indels {
    my ( $name, $var_num, ) = @_;
    
    # first check if this has already been done
    my $output_dir = File::Spec->catfile(
                $options{output_directory}, 'dindel',
                $name, join(q{.}, $name, $var_num, ), ); 
    my $selected_var_file = File::Spec->catfile(
        $output_dir, 'selected_variants.txt' );
    my $final_library_file = File::Spec->catfile(
        $output_dir, 'libraries.txt' );
    if( -e $selected_var_file && -s $selected_var_file &&
        -e $final_library_file && -s $final_library_file ){
        return( $selected_var_file, $final_library_file );
    }
    else{
        my $bam_file = File::Spec->catfile( $output_bam_dir, join(q{.}, $name, $var_num, 'bam', ), );
        my $output_file = File::Spec->catfile(
                    $output_dir, 'extract_indels',
                    join(q{.}, $name, $var_num, 'dindel_extract_indels', ), );
        my $out_file = File::Spec->catfile(
                    $output_dir, 'extract_indels',
                    'dindel_extract_indels.o', );
        my $error_file = File::Spec->catfile(
                    $output_dir, 'extract_indels',
                    'dindel_extract_indels.e', );
        
        my $cmd = join(q{ },
            $options{dindel_bin},
            '--analysis getCIGARindels',
            "--bamFile $bam_file",
            join(q{ }, '--ref', $options{reference}, ),
            "--outputFile $output_file",
            "> $out_file",
            "2> $error_file",
        );
        
        warn $cmd, "\n" if $options{debug};
        system( $cmd ) == 0
            or die "system $cmd failed: $?";
        
        # sort variants file
        my $var_file = join(q{.}, $output_file, 'variants', 'txt' );
        $cmd = join(q{ }, 'sort', '-k1,1', '-k2,2n', $var_file, '>', $selected_var_file );
        
        warn $cmd, "\n" if $options{debug};
        system( $cmd ) == 0
            or die "system $cmd failed: $?";
        
        # check that selected_variants file has non-zero size;
        if( -z $selected_var_file ){
            return;
        }
        
        # copy libraries file
        my $lib_file = join(q{.}, $output_file, 'libraries', 'txt' );
        $cmd = join(q{ }, 'cp', $lib_file, $final_library_file, );
        
        warn $cmd, "\n" if $options{debug};
        system( $cmd ) == 0
            or die "system $cmd failed: $?";
        
        return( $selected_var_file, $final_library_file );
    }
}

sub dindel_make_windows {
    my ( $name, $var_num, $selected_var_file, ) = @_;
    
    # check for windows files
    my $output_dir = File::Spec->catfile(
                $options{output_directory}, 'dindel',
                $name, join(q{.}, $name, $var_num, ), ); 
    my $window_dir = File::Spec->catfile(
                $output_dir, 'windows', );
    
    opendir(my $windowfh, $window_dir);
    my @window_files = ();
    foreach my $file (readdir($windowfh)) {
        if ($file =~ /window\.\d+\.txt/) {
            push(@window_files, $file);
        }
    }
    
    if( @window_files ){
        return @window_files;
    }
    else{
        my $make_windows_py = File::Spec->catfile(
            $options{dindel_scripts},
            'makeWindows.py',
        );
        my $window_prefix = File::Spec->catfile(
                    $output_dir, 'windows',
                    'window', );
        my $out_file = File::Spec->catfile(
                    $output_dir, 'windows',
                    'dindel_make_windows.o', );
        my $error_file = File::Spec->catfile(
                    $output_dir, 'windows',
                    'dindel_make_windows.e', );
        my $cmd = join(q{ },
            'python',
            $make_windows_py,
            "--inputVarFile  $selected_var_file",
            "--windowFilePrefix $window_prefix",
            "--numWindowsPerFile 1",
            "> $out_file",
            "2> $error_file",
        );
        
        warn $cmd, "\n" if $options{debug};
        system($cmd) == 0
            or die "system $cmd failed: $?";
        
        # get window files
        my $window_dir = File::Spec->catfile(
                    $output_dir, 'windows', );
        
        opendir(my $windowfh, $window_dir);
        my @window_files = ();
        foreach my $file (readdir($windowfh)) {
            if ($file =~ /window\.\d+\.txt/) {
                push(@window_files, $file);
            }
        }
        return @window_files;
    }
}

sub dindel_realign_windows {
    my ( $name, $var_num, $window_files, $lib_file ) = @_;
    
    # check for glf files
    my @glf_files;
    my $all_glf_files = 1;
    my $output_dir = File::Spec->catfile(
                $options{output_directory}, 'dindel',
                $name, join(q{.}, $name, $var_num, ), );
    
    foreach my $window_file ( @{$window_files} ){
        my $window_out_prefix = $window_file;
        $window_out_prefix =~ s/\.txt \z//xms;
        $window_out_prefix = File::Spec->catfile(
                $output_dir, 'windows', $window_out_prefix, );
        my $glf_file = join(q{.}, $window_out_prefix, 'glf', 'txt', );
        if( !-e $glf_file || -z $glf_file ){
            $all_glf_files = 0;
        }
        else{
            push @glf_files, $glf_file;
        }
    }
    
    if( $all_glf_files ){
        return @glf_files;
    }
    else{
        my $bam_file = File::Spec->catfile( $output_bam_dir, join(q{.}, $name, $var_num, 'bam', ), );
        
        my @glf_files;
        foreach my $window_file ( @{$window_files} ){
            my $window_out_prefix = $window_file;
            $window_out_prefix =~ s/\.txt \z//xms;
            my $window_file = File::Spec->catfile(
                    $output_dir, 'windows', $window_file, );
            $window_out_prefix = File::Spec->catfile(
                    $output_dir, 'windows', $window_out_prefix, );
            my $out_file = File::Spec->catfile(
                    $output_dir, 'realign_windows.o', );
            my $error_file = File::Spec->catfile(
                    $output_dir, 'realign_windows.e', );
            
            my $cmd = join(q{ },
                $options{dindel_bin},
                '--analysis indels',
                "--bamFile $bam_file",
                '--doDiploid',
                "--maxRead 50000",
                join(q{ }, '--ref', $options{reference}, ),
                "--varFile $window_file",
                "--libFile $lib_file",
                "--outputFile $window_out_prefix",
                "> $out_file",
                "2> $error_file",
            );
            
            warn $cmd, "\n" if $options{debug};
            system($cmd) == 0
                or die "system $cmd failed: $?";
            
            my $glf_file = join(q{.}, $window_out_prefix, 'glf', 'txt', );
            if( !-e $glf_file ){
                die "Dindel realign windows: Couldn't find glf file $glf_file.\n";
            }
            push @glf_files, $glf_file;
        }    
        return @glf_files;
    }
}

sub dindel_make_vcf_file {
    my ( $name, $var_num, $glf_files, ) = @_;

    my $output_dir = File::Spec->catfile(
                $options{output_directory}, 'dindel',
                $name, join(q{.}, $name, $var_num, ), );
    my $output_vcf_file = File::Spec->catfile(
        $output_dir, 'calls.vcf', );
    
    # check whether vcf file exists
    if( -e $output_vcf_file && -s $output_vcf_file ){
        return $output_vcf_file;
    }
    else{
        my $merge_output_py = File::Spec->catfile(
            $options{dindel_scripts},
            'mergeOutputDiploid.py',
        );
        
        # make glf file of file names
        my $glf_fofn = File::Spec->catfile( $output_dir, 'glf.fofn');
        open my $ofh, '>', $glf_fofn;
        print $ofh join("\n", @{$glf_files} ), "\n";
        close($ofh);
        
        my $cmd = join(q{ },
            'python',
            $merge_output_py,
            "--inputFiles $glf_fofn",
            "--outputFile $output_vcf_file",
            "--sampleID $name",
            join(q{ }, '--ref', $options{reference}, ),
        );
        
        warn $cmd, "\n" if $options{debug};
        system($cmd) == 0
            or die "system $cmd failed: $?";
        
        return $output_vcf_file;
    }
}

sub output_vcf_header_for_subplex {
    my ( $vcf_fh, $plex, $well_block, ) = @_;

    my $ref_line = join("=", '##reference',
        $options{reference}, );
    
    my $header = << "END_HEADER";
##fileformat=VCFv4.0
##source=Dindel
$ref_line
##INFO=<ID=DP,Number=1,Type=Integer,Description="Total number of reads in haplotype window">
##INFO=<ID=AD,Number=2,Type=Integer,Description="Allele Depths">
##INFO=<ID=NF,Number=1,Type=Integer,Description="Number of reads covering non-ref variant on forward strand">
##INFO=<ID=NR,Number=1,Type=Integer,Description="Number of reads covering non-ref variant on reverse strand">
##INFO=<ID=NFS,Number=1,Type=Integer,Description="Number of reads covering non-ref variant site on forward strand">
##INFO=<ID=NRS,Number=1,Type=Integer,Description="Number of reads covering non-ref variant site on reverse strand">
##FORMAT=<ID=GT,Number=1,Type=String,Description="Genotype">
##FORMAT=<ID=GQ,Number=1,Type=Integer,Description="Genotype quality">
##ALT=<ID=DEL,Description="Deletion">
##FILTER=<ID=q20,Description="Quality below 20">
##FILTER=<ID=hp10,Description="Reference homopolymer length was longer than 10">
##FILTER=<ID=fr0,Description="Non-ref allele is not covered by at least one read on both strands">
##FILTER=<ID=wv,Description="Other indel in window had higher likelihood">
END_HEADER

    my @header_cols = ( "#CHROM ", qw{ POS ID REF ALT QUAL FILTER INFO FORMAT } );
    my @samples;
    if( @{ $well_block->{sample_names} } ){
        @samples = @{ $well_block->{sample_names} }
    }
    else{
        @samples = map { join("_", $plex->{name}, $_, ) } @{ $well_block->{well_ids} }
    }
    my $i = -1;
    my %index_for = map { $i++; $_ => $i } @samples;
    push @header_cols, @samples;
    
    print $vcf_fh $header;
    print $vcf_fh join("\t", @header_cols ), "\n";
    
    return ( \@samples, \%index_for, );
}

sub parse_yaml_file {
    my ( $yaml_file, ) = @_;
    my $plex_info;
    if( -e $yaml_file ){
        $plex_info = parse_yaml_plex_file( $yaml_file );
    }
    else{
        my $yaml_file =  File::Spec->catfile( $options{output_directory}, $yaml_file, );
        if( -e $yaml_file ){
            $plex_info = parse_yaml_plex_file( $yaml_file );
        }
        else{
            die "Couldn't find YAML file: $yaml_file!\n";
        }
    }
    
    my %crispr_seen;
    my %crispr_pair_seen;
    
    my $start_group_num = 1;
    foreach my $plate ( @{$plex_info->{plates}} ){
        foreach my $well_block ( @{ $plate->{wells} } ){
            
            my @well_ids;
            foreach my $well_id ( split /,/, $well_block->{well_ids} ){
                if( $well_id =~ m/\A    [A-H][0-9]+ # well id
                                        \-          # hyphen
                                        [A-H][0-9]+ # well id
                                    \z/xms ){
                    my $plate_obj = Labware::Plate->new(
                       plate_type => 96,
                       fill_direction => 'row',
                    );
                    
                    push @well_ids, $plate_obj->range_to_well_ids( $well_id );
                }
                elsif( $well_id =~ m/\A [A-H][0-9]+ \z/xms ){
                    push @well_ids, $well_id;
                }
                else{
                    #die "Couldn't parse well id string, ", $plex->{well_info}->{well_ids},
                    #    ", from plex: ", $plex->{name}, "\n";
                    push @well_ids, $well_id;
                }
            }
            $well_block->{well_ids} = \@well_ids;
            
            my @sample_ids;
            foreach my $sample_id ( split /,/, $well_block->{sample_names} ){
                if( $sample_id =~ m/\A  [A-H][0-9]+   # well id
                                        \-              # hyphen
                                        [A-H][0-9]+     # well id
                                    \z/xms ){
                    my $plate_obj = Labware::Plate->new(
                       plate_type => 96,
                       fill_direction => 'row',
                    );
                    
                    push @sample_ids, $plate_obj->range_to_well_ids( $sample_id );
                }
                elsif( $sample_id =~ m/\A [A-H][0-9]+ \z/xms ){
                    push @sample_ids, $sample_id;
                }
                else{
                    #die "Couldn't parse sample id string, ", $plex->{well_info}->{sample_names},
                    #    ", from plex: ", $plex->{name}, "\n";
                    push @sample_ids, $sample_id;
                }
            }
            $well_block->{sample_names} = \@sample_ids;
            
            my $well_ids = join(",", @{ $well_block->{well_ids} } );
            foreach my $plex ( @{$well_block->{plexes}} ){
                foreach my $region_info ( @{$plex->{region_info}} ){
                    my ( $chr, $start, $end, $strand ) = parse_position( $region_info->{region} );
                    my @crisprs;
                    foreach my $crispr_name ( @{ $region_info->{crisprs} } ){
                        my $group_num = $start_group_num;
                        while(1){
                            if( !exists $crisprs_for_groups{ $group_num }{ $plate->{name} }{ $well_ids } ){
                                $crisprs_for_groups{ $group_num }{ $plate->{name} }{ $well_ids } = $crispr_name;
                                $groups_for_crisprs{ $plate->{name} }{ $well_ids }{ $crispr_name } = $group_num;
                                last;
                            }
                            else{
                                $group_num++;
                            }
                        }
                        my $crRNA = $crispr_design->create_crRNA_from_crRNA_name( $crispr_name, );
                        if( !exists $crispr_seen{ $crispr_name } ){
                            $crispr_tree->insert_interval_into_tree( $crRNA->chr, $crRNA->cut_site, $crRNA->cut_site, $crRNA );
                            $crispr_seen{ $crispr_name } = 1;
                        }
                        push @crisprs, $crRNA;
                    }
                    if( scalar @crisprs == 2 ){
                        # sort crRNAs by position
                        @crisprs = sort { $a->cut_site <=> $b->cut_site } @crisprs;
                        my $pair_name = join(":",
                                $crisprs[0]->chr,
                                $crisprs[0]->cut_site,
                                $crisprs[1]->cut_site,
                            );
                        if( !exists $crispr_pair_seen{ $pair_name } ){
                            $crispr_pair_seen{ $pair_name } = 1;
                            $crispr_pair_tree->insert_interval_into_tree(
                                $crisprs[0]->chr,
                                $crisprs[0]->cut_site,
                                $crisprs[1]->cut_site,
                                \@crisprs );
                        }
                    }
                    $region_info->{crisprs} = \@crisprs;
                }
            }
            
        }
        
        $start_group_num = ( sort {$b <=> $a} keys %crisprs_for_groups )[0] + 1;
    }
    
    warn Dumper( $plex_info, %crisprs_for_groups, %groups_for_crisprs, ) if( $options{debug} > 0 );
    
    if( $options{verbose} ){
        print "Crispr groups:\n";
        foreach my $plate_num ( sort { $a <=> $b } keys %groups_for_crisprs  ){
            foreach my $well_ids ( sort keys $groups_for_crisprs{$plate_num} ){
                foreach my $crispr_name ( sort keys $groups_for_crisprs{$plate_num}{$well_ids} ){
                    print join("\t", $plate_num, $well_ids, $crispr_name,
                        $groups_for_crisprs{$plate_num}{$well_ids}{$crispr_name},
                        ), "\n";
                }
            }
        }
    }
    
    return $plex_info;
}

sub parse_yaml_plex_file {
    my ( $yaml_file, ) = @_;
    my $yaml = YAML::Tiny->read($yaml_file);
    
    if ( !$yaml ) {
        confess sprintf 'YAML file (%s) is invalid: %s', $yaml_file,
          YAML::Tiny->errstr;
    }
    
    if( scalar @{$yaml} > 1 ){
        confess "More than one plex in YAML file!";
    }
    return $yaml->[0];
}

sub make_new_plate {
    my ( $group_number, ) = @_;
    my $plate = Labware::Plate->new(
        plate_name => $group_number,
        plate_type => '96',
        fill_direction => 'column',
    );
    return $plate;
}

sub parse_position {
    my ( $posn, ) = @_;
    
    my ( $chr, $region, $strand ) = split /:/, $posn;
    my ( $start, $end ) = split /-/, $region;
    
    return ( $chr, $start, $end, $strand );
}

sub get_and_check_options {
    
    GetOptions(
        \%options,
        'output_directory=s',
        'output_file=s',
        'sample_directory=s',
        'pindel_directory=s',
        'pc_filter=f',
        'consensus_filter=i',
        'overlap_threshold=i',
        'low_coverage_filter:i',
        'pindel_path=s',
        'no_pindel',
        'no_dindel',
        'dindel_bin=s',
        'dindel_scripts=s',
        'vcftools_path=s',
        'reference=s',
        'assembly=s',
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
    
    if( !$options{output_directory} ){
        $options{output_directory} = 'results';
    }
    
    # CHECK SAMPLE DIRECTORY EXISTS
    if( ! $options{sample_directory} ){
        $options{sample_directory} = 'sample-bams';
    }
    if( !-d $options{sample_directory} || !-r $options{sample_directory} || !-x $options{sample_directory} ){
        my $err_msg = join(q{ }, "Sample directory: ", $options{sample_directory}, " does not exist or is not readable/executable!\n" );
        pod2usage( $err_msg );
    }
    
    # SET PINDEL DIRECTORY TO DEFAULT IF NOT SET
    if( !$options{pindel_directory} ){
        $options{pindel_directory} = 'pindel';
    }
    
    # SET DEFAULT FOR FILTERING
    if( !$options{pc_filter} ){
        $options{pc_filter} = 0.01
    }
    if( !defined $options{consensus_filter} ){
        $options{consensus_filter} = 50;
    }
    
    # CHECK PINDEL PATH EXISTS
    if( !$options{no_pindel} ){
        if( $options{pindel_path} ){
            if( !-d $options{pindel_path} || !-r $options{pindel_path} || !-x $options{pindel_path} ){
                my $err_msg = join(q{ }, "Pindel directory:",
                    $options{pindel_path},
                    "does not exist or is not readable/executable!\n" );
                pod2usage( $err_msg );
            }
            $options{pindel_bin} = File::Spec->catfile( $options{pindel_path}, 'pindel' );
            
            # Check pindel can be run
            my $pindel_test_cmd = join(q{ }, $options{pindel_bin}, '-h', );
            open my $pindel_fh, '-|', $pindel_test_cmd;
            my @lines;
            while(<$pindel_fh>){
                chomp;
                push @lines, $_;
            }
            if( $lines[1] !~ m/\A Pindel\sversion/xms ){
                my $msg = join("\n", 'Could not run pindel', @lines, ) . "\n";
                pod2usage( $msg );
            }
        }
        else{
            $options{pindel_bin} = which( 'pindel' );
            if( !$options{pindel_bin} ){
                my $msg = join("\n", 'Could not find pindel in the current path:',
                    join(q{ }, 'Either install pindel in the current path,',
                        'alter the path to include the pindel directory',
                        'or supply the path to pindel as --pindel_path.', ),
                    ) . "\n";
                pod2usage( $msg );
            }
        }
        
        # CHECK VCFTOOLS PATH
        if( $options{vcftools_path} ){
            if( ! -d $options{vcftools_path} || ! -r $options{vcftools_path} ||
                ! -x $options{vcftools_path} ){
                my $err_msg = join(q{ }, "Vcftools directory: ", $options{vcftools_path}, " does not exist or is not readable/executable!\n" );
                pod2usage( $err_msg );
            }
            # concat dir and names
            $options{vcfconcat} = File::Spec->catfile($options{vcftools_path}, 'vcf-concat' );
            $options{vcfsort} = File::Spec->catfile($options{vcftools_path}, 'vcf-sort' );
        }
        else{
            $options{vcfconcat} = which( 'vcf-concat' );
            $options{vcfsort} = which( 'vcf-sort' );
        }
        # check vcf-concat and vcf-sort
        my $vcf_concat_test = join(q{ }, $options{vcfconcat}, '-h', '2>&1' );
        open my $vcf_fh, '-|', $vcf_concat_test;
        my @lines = ();
        while(<$vcf_fh>){
            chomp;
            push @lines, $_;
        }
        if( $lines[0] ne 'About: Convenience tool for concatenating VCF files (e.g. VCFs split by chromosome).' ){
            my $msg = join("\n", 'Could not run vcf-concat: ', @lines, ) . "\n";
            pod2usage( $msg );
        }
        
        my $vcf_sort_test = join(q{ }, $options{vcfsort}, '-h', '2>&1' );
        open $vcf_fh, '-|', $vcf_sort_test;
        @lines = ();
        while(<$vcf_fh>){
            chomp;
            push @lines, $_;
        }
        if( $lines[0] ne 'Usage: vcf-sort > out.vcf' ){
            my $msg = join("\n", 'Could not run vcf-sort: ', @lines, ) . "\n";
            pod2usage( $msg );
        }
    }
    
    # CHECK DINDEL PATHS
    if( !$options{no_dindel}){
        if( !$options{dindel_bin} ){
            $options{dindel_bin} = which( 'dindel' );
        }
        else{
            # Check dindel can be run
            my $dindel_test_cmd = join(q{ }, $options{dindel_bin}, '-h', );
            open my $dindel_fh, '-|', $dindel_test_cmd;
            my @lines;
            while(<$dindel_fh>){
                chomp;
                push @lines, $_;
            }
            if( $lines[1] !~ m/\A Pindel\sversion/xms ){
                my $msg = join("\n", 'Could not run dindel: ', @lines, ) . "\n";
                pod2usage( $msg );
            }
        }
        
        if( !$options{dindel_scripts} ){
            my $err_msg = join(q{ }, 'Option --dindel_scripts',
                'must be specified unless the --no_dindel option is set.',
                ) . "\n";
            pod2usage( $err_msg );
        }
        else{
            if( !-d $options{dindel_scripts} || !-r $options{dindel_scripts} ||
               !-x $options{dindel_scripts} ){
                my $err_msg = join(q{ }, "Dindel scripts directory:",
                    $options{dindel_scripts},
                    "does not exist or is not readable/executable!\n" );
                pod2usage( $err_msg );
            }
        }
    }
    
    # CHECK REFERENCE EXISTS
    if( exists $options{reference} ){
        if( ! -e $options{reference} || ! -f $options{reference} || ! -r $options{reference} ){
            my $err_msg = join(q{ }, "Reference file:", $options{reference}, "does not exist or is not readable!\n" );
            pod2usage( $err_msg );
        }
    }
    
    if( !$options{debug} ){
        $options{debug} = 0;
    }
    
    if( !$options{assembly} ){
        $options{assembly} = 'Zv9';
    }
    
    print "Settings:\n", map { join(' - ', $_, defined $options{$_} ? $options{$_} : 'off'),"\n" } sort keys %options if $options{verbose};
}

__END__

=pod

=head1 NAME

count_indel_reads_from_sam.pl

=head1 DESCRIPTION

Description

=cut

=head1 SYNOPSIS

    count_indel_reads_from_sam.pl [options] YAML file
        --output_directory      directory for output files                  default: results
        --output_file           name for the output file
        --sample_directory      directory to find sample bam files          default: sample-bams
        --pindel_directory      directory to find pindel output files       default: pindel
        --pc_filter             threshold for the percentage of reads
                                that a variant has to achieve for output    default: 0.01
        --consensus_filter      threshold for the length of the consensus
                                alt read                                    default: 50
        --overlap_threshold     distance from the predicted cut-site that
                                a variant must be within to be counted      default: 10
        --low_coverage_filter   turns on a filter to discard variants that
                                fall below an absolute number of reads      default: 10
        --pindel_path           file path for the pindel program            
        --no_pindel             option to skip using pindel
        --no_dindel             option to skip using dindel
        --vcftools_path         file path for vcftools
        --reference             genome reference file
        --assembly              name for the genome assembly
        --help                  print this help message
        --man                   print the manual page
        --debug                 print debugging information
        --verbose               turn on verbose output


=head1 ARGUMENTS

=over

=item B<YAML file>

Configuration YAML file which tells the script which samples to process and which regions to look at.
An example is shown below.

    ---
    lane: 1
    name: ex_plex
    plates:
      -
        name: 1
        wells:
          -
            indices: 1,2,3,4,5,6,7,8
            plexes:
              -
                name: 1
                region_info:
                  -
                    crisprs:
                      - crRNA:CHR:START-END:STRAND
                    gene_name: gene
                    region: CHR:START-END:STRAND
            sample_names: 1_A01,1_B01,1_C01,1_D01,1_E01,1_F01,1_G01,1_H01
            well_ids: A01,B01,C01,D01,E01,F01,G01,H01
    run_id: 100


=back

=head1 OPTIONS

=item B<--output_directory>

Directory for output files [default: results]

=item B<--output_file>

name for the output file. If not specified the file name is Plex_name.txt

=item B<--sample_directory>

Directory in which to find the sample bam files [default: sample-bams]

=item B<--pindel_directory>

Directory in which to find the pindel output files [default: pindel]

=item B<--pc_filter>

A threshold for the percentage of reads that a variant has to achieve for output

[default: 0.01 (1%)]

=item B<--consensus_filter>

A threshold for the length of the consensus alt read to
filter out primer-dimer artifacts [default: 50]

=item B<--overlap_threshold>

A threshold for the distance from the predicted guideRNA cut-site that a indel must be within to be counted.
[default: 10]
A range is constructed and the cut-site must fall within this range.
The range is:
    variant_start - overlap_threshold  TO  variant_end + overlap_threshold

=item B<--low_coverage_filter>

Turns on filtering of variants by depth.
If no value is supplied the default level of filtering in 10 reads supporting the variant.

=item B<--pindel_path>

Path for the pindel program

=item B<--no_pindel>

option to skip running pindel

=item B<--no_dindel>

option to skip using Dindel

=item B<--vcftools_path>

file path for vcftools

=item B<--reference>

Path to the genome reference file.

=item B<--assembly>

Name for the genome assembly

=over

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

This software is Copyright (c) 2014,2015 by Genome Research Ltd.

This is free software, licensed under:

  The GNU General Public License, Version 3, June 2007

=cut