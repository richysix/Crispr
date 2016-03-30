#!/usr/bin/env perl

# PODNAME: downsample_bams_for_candidate_indels.pl
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
use File::Find::Rule;
use File::Path qw(make_path);
use List::Util qw(sum);
use File::Which;
use DateTime;
use Storable;
use Clone qw(clone);
use IO::Handle;
use Hash::Merge;

use Crispr;
use Tree::GenomicIntervalTree;
use Labware::Plate;
use Bio::DB::Sam;
use Bio::DB::Bam::Alignment;

# get options
my %options;
get_and_check_options();

if( $options{debug} ){ use Data::Dumper; }
Readonly my $INTERVAL_EXTENDER => defined $options{overlap_threshold} ? $options{overlap_threshold} : 10;
Readonly my $PER_VAR_COVERAGE_FILTER => !defined $options{low_coverage_per_variant_filter} ? 0
    :   $options{low_coverage_per_variant_filter};
Readonly my $PER_AMP_COVERAGE_FILTER => !defined $options{low_coverage_filter} ? 0
    :   $options{low_coverage_filter};

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

# go through all the sample bams from the yaml file
my ( $results, $outliers, );
my %variants_seen;
print "CIGAR string analysis...\n" if $options{verbose};
my $prefix = exists $plex_info->{prefix} ?   $plex_info->{prefix} :   $plex_info->{name};
my $combined_results_filename = File::Spec->catfile( $options{output_directory}, $prefix . '.combined_results.pd' );
my $data_object;

Readonly my $DOWNSAMPLE_LIMIT => 50;

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

# build up consensus sequence for top variants
# also output alignments to bam file
foreach my $plate ( @{ $plex_info->{plates} } ){
    foreach my $well_block ( @{ $plate->{wells} } ){
        foreach my $plex ( @{ $well_block->{plexes} } ){
            # make plex directory for bams
            my $output_bam_dir = File::Spec->catfile( $options{output_directory}, 'bams', $plex->{name} );
            # check whether directory already exists and create it if not
            if( !-e $output_bam_dir ){
                my @created_dirs = make_path( $output_bam_dir );
                if( !@created_dirs ){
                    die join(q{ }, "Could not create directory for ", $plex->{name}, "in",
                            File::Spec->catfile( $options{output_directory}, 'bams'),
                            "for output bam files!" ), "\n";
                }
            }
            # counter
            my $i = 0;
            my @indices;
            # check for indices in the YAML hash. 
            if( exists $well_block->{indices} ){
                @indices = split /,/, $well_block->{indices};
            }
            foreach my $sample ( @{ $well_block->{sample_names} } ){
                my $var_num = 1;
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
                    next if( !exists $results_hash->{read_count} || $results_hash->{read_count} <= $PER_AMP_COVERAGE_FILTER );
                    
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
                        # Remove variants that are below threshold
                        my @variants;
                        foreach my $variant ( keys %{ $results_hash->{indels}->{$crispr_name} } ){
                            if( $results_hash->{indels}->{$crispr_name}->{$variant}->{count} < $PER_VAR_COVERAGE_FILTER ){
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
                                    my $read_name = join(":", $align->query->name, $align->strand, );
                                    if( $results_hash->{indels}->{$crispr_name}->{$variant}->{count} > $DOWNSAMPLE_LIMIT ){
                                        my $fraction = $DOWNSAMPLE_LIMIT / $results_hash->{indels}->{$crispr_name}->{$variant}->{count};
                                        if( rand() < $fraction ){
                                            $read_names{ $variant }{ $read_name } = 1;
                                        }
                                    } else {
                                        $read_names{ $variant }{ $read_name } = 1;
                                    }
                                }
                            }
                        }
                    }
                    
                    warn Dumper( %read_names ) if $options{debug} > 2;
                    
                    # open bam file and get header
                    my $in_bam = Bio::DB::Bam->open($infile, "r");
                    my $header = $in_bam->header();
                    
                    # open output bam file for each variant and write header
                    my %bam_fhs;
                    foreach my $variant ( keys %read_names ){
                        my $outfile = File::Spec->catfile( $options{output_directory}, 'bams', $plex->{name}, join(".", $name, $var_num, 'bam' ) );
                        my $out_bam = Bio::DB::Bam->open($outfile, "w");
                        $out_bam->header_write( $header );
                        $bam_fhs{ $variant } = $out_bam;
                        # add number for var to results hash
                        foreach my $crispr_name ( keys %{ $results_hash->{indels} } ){
                            if( exists $results_hash->{indels}->{$crispr_name}->{$variant} ){
                                $results_hash->{indels}->{$crispr_name}->{$variant}->{var_num} = $var_num;
                            }
                            warn "VAR_NUM:$var_num - $variant\n",
                                Dumper( $results_hash->{indels}->{$crispr_name}->{$variant} ) if $options{debug} > 1;
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
                            my $read_name = $alignment->qname . ":" . ($alignment->reversed ? "-1" : "1" );
                            if( exists $read_names->{ $variant}{ $read_name } ){
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

# find all bam files in the bams directory and index them
my $rule = File::Find::Rule->file->name("*.bam")->start( $output_bam_dir );
while ( defined ( my $bam_file = $rule->match ) ) {
    warn $bam_file, "\n" if $options{debug};
    # index bam file with samtools
    my $cmd = qq{ samtools index $bam_file };
    system( $cmd ) == 0 or die "system $cmd failed: $?";
}

# store combined data for retrieval by count_indels
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
        'sample_directory=s',
        'pc_filter=f',
        'consensus_filter=i',
        'overlap_threshold=i',
        'low_coverage_filter:i',
        'low_coverage_per_variant_filter:i',
        'reference=s',
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
    
    # SET DEFAULT FOR FILTERING
    if( !$options{pc_filter} ){
        $options{pc_filter} = 0.01
    }
    if( !defined $options{consensus_filter} ){
        $options{consensus_filter} = 50;
    }
    if( defined $options{low_coverage_filter} &&
        $options{low_coverage_filter} == 0 ){
        $options{low_coverage_filter} = 100;
    }
    if( defined $options{low_coverage_per_variant_filter} &&
        $options{low_coverage_per_variant_filter} == 0 ){
        $options{low_coverage_per_variant_filter} = 10;
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
        --sample_directory      directory to find sample bam files          default: sample-bams
        --pc_filter             threshold for the percentage of reads
                                that a variant has to achieve for output    default: 0.01
        --consensus_filter      threshold for the length of the consensus
                                alt read                                    default: 50
        --overlap_threshold     distance from the predicted cut-site that
                                a variant must be within to be counted      default: 10
        --low_coverage_filter   turns on a filter to discard samples that
                                fall below an absolute number of reads      default: 100
        --low_coverage_per_variant_filter
                                turns on a filter to discard variants that
                                fall below an absolute number of reads      default: 10
        --reference             genome reference file
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

=over

=item B<--output_directory>

Directory for output files [default: results]

=item B<--sample_directory>

Directory in which to find the sample bam files [default: sample-bams]

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

Turns on filtering of samples by depth.
If no value is supplied the default level of filtering is 100 reads per amplicon.

=item B<--low_coverage_per_variant_filter>

Turns on filtering of variants by depth.
If no value is supplied the default level of filtering is 10 reads supporting the variant.

=item B<--reference>

Path to the genome reference file.

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
