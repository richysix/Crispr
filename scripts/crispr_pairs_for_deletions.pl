#!/usr/bin/env perl
use warnings; use strict;
use Getopt::Long;
use autodie;
use Pod::Usage;
use List::MoreUtils qw{ all none minmax };
use Readonly;
use Data::Dumper;

use Bio::EnsEMBL::Registry;
use Crispr;
use Crispr::Target;
use Crispr::CrisprPair;

#get current date
use DateTime;
my $date_obj = DateTime->now();
my $todays_date = $date_obj->ymd;

# get options
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
my $gene_adaptor = Bio::EnsEMBL::Registry->get_adaptor( $options{species}, 'core', 'gene' );
my $exon_adaptor = Bio::EnsEMBL::Registry->get_adaptor( $options{species}, 'core', 'exon' );
my $transcript_adaptor = Bio::EnsEMBL::Registry->get_adaptor( $options{species}, 'core', 'transcript' );
my $slice_adaptor = Bio::EnsEMBL::Registry->get_adaptor( $options{species}, 'core', 'slice' );
my $rnaseq_gene_adaptor = Bio::EnsEMBL::Registry->get_adaptor( $options{species}, 'otherfeatures', 'gene' );
my $rnaseq_transcript_adaptor = Bio::EnsEMBL::Registry->get_adaptor( $options{species}, 'otherfeatures', 'transcript' );

# make basename for output files
my $basename = $todays_date;
$basename =~ s/\A/$options{file_base}_/xms if( $options{file_base} );

# open output files
my $output_filename = $basename . '.all_pairs.txt';
open my $out_fh_1, '>', $output_filename or die "Couldn't open file, $output_filename:$!\n";

$output_filename = $basename . '.highest_scoring_pairs.txt';
open my $out_fh_2, '>', $output_filename or die "Couldn't open file, $output_filename:$!\n";

# make design object
my $crispr_design = Crispr->new(
    species => $options{species},
    target_genome => $options{target_genome},
    annotation_file => $options{annotation_file},
    target_seq => $options{target_sequence},
    five_prime_Gs => $options{num_five_prime_Gs},
    scored => 0,
    slice_adaptor => $slice_adaptor,
    debug => $options{debug},
);

print "Checking targets...\n" if $options{verbose};
my $targets_for;
my @target_ids;
my $check_five_prime_score;
# identify input type for each line and make a and b targets for each one
# INPUT SHOULD BE TAB-SEPARATED: TARGET_ID  REQUESTOR   [GENE_ID]
while(<>){
    chomp;
    s/,//g;
    
    my @columns = split /\t/xms;
    
    # guess id type
    $targets_for =  $columns[0] =~ m/\AENS[A-Z]*G[0-9]{11}# gene id/xms         ?   targets_from_gene( $targets_for, \@columns, )
        :           $columns[0] =~ m/\ALRG_[0-9]+/xms                           ?   targets_from_gene( $targets_for, \@columns, )
        :           $columns[0] =~ m/\ARNASEQG[0-9]+/xms                        ?   targets_from_gene( $targets_for, \@columns, )
        :           $columns[0] =~ m/\AENS[A-Z]*E[0-9]{11}# exon id/xms         ?   targets_from_exon( $targets_for, \@columns, )
        :           $columns[0] =~ m/\AENS[A-Z]*T[0-9]{11}# transcript id/xms   ?   targets_from_transcript( $targets_for, \@columns, )
        :           $columns[0] =~ m/\ARNASEQT[0-9]{11}# transcript id/xms      ?   targets_from_transcript( $targets_for, \@columns, )
        :           $columns[0] =~ m/\A[\w.]+:\d+\-\d+[:01-]*# position/xms     ?   targets_from_posn( $targets_for, \@columns, )
        :                                                                           no_match( $targets_for, \@columns )
        ;
}

die "Something went wrong. There aren't any targets!\n" if !$targets_for;

# check that at least one of the target pairs for a given gene has some crRNAs
foreach my $target_id ( keys %{$targets_for} ){
    if( !@{$targets_for->{ $target_id }} ){
        warn "## No crRNAs for any of the targets for $target_id\n";
    }
}
warn "##\n";

## score off-targets
if( !@{$crispr_design->targets} ){
    warn "There are no targets to score.\n";
    exit 1;
}
# filter for variation if option selected
if( defined $options{variation_file} ){
    foreach my $target ( @{ $crispr_design->targets } ){
        $crispr_design->filter_crRNAs_from_target_by_snps_and_indels( $target, $options{variation_file}, 1 );
        
        if( !@{$target->crRNAs} ){
            #remove from targets if there are no crispr sites for that target
            warn "No crRNAs for ", $target->target_name, " after filtering by variation\n";
            $crispr_design->remove_target( $target );
        }
    }
}

# score off targets using bwa
print "Scoring off-targets...\n" if $options{verbose};
$crispr_design->find_off_targets( $crispr_design->all_crisprs, $basename, );

if( $options{debug} ){
    warn "INITIAL crRNAs:\n";
    foreach my $target ( @{$crispr_design->targets} ){
        foreach ( @{ $target->crRNAs } ){
            warn join("\t", $_->target_info_plus_crRNA_info, ), "\n";
        }
    }
}

# and do off-targets as pairs, default window size = 10000
print "Scoring off-targets in pairs...\n" if $options{verbose};

Readonly my $WINDOW_SIZE => defined $options{max_off_target_separation}    ?   $options{max_off_target_separation}
    :                                                                       10000;

Readonly my $MIN_CRISPR_SEPARATION => defined $options{min_crispr_separation}  ?   $options{min_crispr_separation}
    :                                                               30;
Readonly my $MAX_CRISPR_SEPARATION => defined $options{max_crispr_separation}  ?   $options{max_crispr_separation}
    :                                                               60;
Readonly my $OPT_CRISPR_SEPARATION => defined $options{opt_crispr_separation}  ?   $options{opt_crispr_separation}
    :   $MIN_CRISPR_SEPARATION + int ( $MAX_CRISPR_SEPARATION - $MIN_CRISPR_SEPARATION )/2;

# go through all targets
my $crispr_pairs_for;
foreach my $target_id ( keys %{$targets_for} ){
    foreach my $targets ( @{$targets_for->{ $target_id }} ){
        my $existing_pairs;
        my $a_target = $targets->[0];
        my $b_target = $targets->[1];
        my $target_name = $a_target->target_name;
        $target_name =~ s/_del_a//xms;
        
        # make a paired crispr object for each combo of a_crRNAs and other crRNAs
        foreach my $a_crRNA ( @{$a_target->crRNAs} ){
            if( !defined $a_crRNA->coding_score && $a_crRNA->target &&
                    $a_crRNA->target_gene_id ){
                my $transcripts;
                my $gene_id = $a_crRNA->target_gene_id;
                my $gene = fetch_gene( [ $gene_id ] );
                if( $gene ){
                    $transcripts = $gene->get_all_Transcripts;
                    $a_crRNA = $crispr_design->calculate_all_pc_coding_scores( $a_crRNA, $transcripts );
                }
            }
            foreach my $b_crRNA ( @{$b_target->crRNAs} ){
                if( !defined $b_crRNA->coding_score && $b_crRNA->target &&
                        $b_crRNA->target_gene_id ){
                    my $transcripts;
                    my $gene_id = $b_crRNA->target_gene_id;
                    my $gene = fetch_gene( [ $gene_id ] );
                    if( $gene ){
                        $transcripts = $gene->get_all_Transcripts;
                        $b_crRNA = $crispr_design->calculate_all_pc_coding_scores( $b_crRNA, $transcripts );
                    }
                }
                # make sure the a_crRNA is first on the chromosome 
                next unless( $a_crRNA->cut_site < $b_crRNA->cut_site );
                my $crispr_pair = Crispr::CrisprPair->new(
                    target_name => $target_id,
                    target_1 => $a_target,
                    target_2 => $b_target,
                    crRNA_1 => $a_crRNA,
                    crRNA_2 => $b_crRNA,
                    paired_off_targets => 0,
                );
                # also check that the separation is not too big
                next unless( $crispr_pair->deletion_size >= $MIN_CRISPR_SEPARATION
                        && $crispr_pair->deletion_size < $MAX_CRISPR_SEPARATION );
                push @{ $crispr_pairs_for->{$target_id} }, $crispr_pair;
                $existing_pairs = 1;
            }
        }
        next if( !$existing_pairs );
        
        # set up look up table
        my %relevant_crRNAs_lookup = map { $_->name => 1 } @{$b_target->crRNAs};
        
        foreach my $a_crRNA ( @{$a_target->crRNAs} ){
            warn $a_crRNA->name, ':', "\n" if $options{debug};
            # add key for this a_crRNA so we get self matches as well
            $relevant_crRNAs_lookup{ $a_crRNA->name } = 1;
            warn "crRNAs lookup:\n", Dumper( %relevant_crRNAs_lookup ) if $options{debug};
            #lookup overlapping intervals
            if( $a_crRNA->off_target_hits->all_off_targets ){
                foreach my $off_target_obj ( $a_crRNA->off_target_hits->all_off_targets ){
                    my $results = $crispr_design->off_targets_interval_tree->fetch_overlapping_intervals(
                        $off_target_obj->chr, $off_target_obj->start - $WINDOW_SIZE, $off_target_obj->end + $WINDOW_SIZE );
                    warn 'WINDOW: ' . $off_target_obj->chr . ':' . join('-', $off_target_obj->start - $WINDOW_SIZE, $off_target_obj->end + $WINDOW_SIZE, ), "\n" if $options{debug};
                    foreach my $off_target_info ( @{$results} ){
                        # check if is the same off-target site
                        next if( $off_target_obj->chr eq $off_target_info->chr && $off_target_obj->start == $off_target_info->start &&
                                $off_target_obj->end == $off_target_info->end && $off_target_obj->strand eq $off_target_info->strand );
                        # check if it's an off-target that we care about
                        next if( !exists $relevant_crRNAs_lookup{ $off_target_info->crRNA_name } );
                        # check whether the off-target matches are on opposite strands
                        next unless( $off_target_obj->strand * $off_target_info->strand eq -1 );
                        
                        warn Dumper( $off_target_info ) if $options{debug};
                        
                        # which one has the first cut-site on the chromosome
                        my $overhang;
                        if( cut_site( $off_target_obj->start, $off_target_obj->end, $off_target_obj->strand ) <=
                            cut_site( $off_target_info->start, $off_target_info->end, $off_target_info->strand ) ){
                            if( $off_target_obj->strand eq '-1' && $off_target_info->strand eq '1' ){
                                # 5' overhang
                                $overhang = '5_prime';
                            }
                            elsif( $off_target_obj->strand eq '1' && $off_target_info->strand eq '-1' ){
                                # 3' overhang
                                $overhang = '3_prime';
                            }
                            else{
                                # This shouldn't happen. Have already checked for ones on the same strand. Complain
                                die "Both off-targets on the same strand but they haven't been filtered. Help!\n";
                            }
                        }
                        else{
                            if( $off_target_info->strand eq '-1' && $off_target_obj->strand eq '1' ){
                                # 5' overhang
                                $overhang = '5_prime';
                            }
                            elsif( $off_target_info->strand eq '1' && $off_target_obj->strand eq '-1' ){
                                # 3' overhang
                                $overhang = '3_prime';
                            }
                            else{
                                # This shouldn't happen. Have already checked for ones on the same strand. Complain
                                die "Both off-targets on the same strand but they haven't been filtered. Help!\n";
                            }
                        }
                        
                        # increment paired_off_targets by correct ammount
                        my $increment = $overhang eq '5_prime'  ?   2
                            :                                       1;
                        # find the right crispr pair
                        my @pairs = grep { $_->name eq $a_crRNA->name . q{_} . $off_target_info->crRNA_name } @{ $crispr_pairs_for->{ $target_id } };
                        if( scalar @pairs == 1){
                            $pairs[0]->increment_paired_off_targets( $increment );
                        }
                    }
                }
            }
            
            # remove key for this a_crRNA ready for the next iteration of the loop
            delete $relevant_crRNAs_lookup{ $a_crRNA->name };
        }
    }
    if( $options{debug} && !exists $crispr_pairs_for->{ $target_id } ){
        map {
                my @a_names = map { $_->name } @{$_->[0]->crRNAs};
                my @b_names = map { $_->name } @{$_->[1]->crRNAs};
                foreach my $a_name ( @a_names ){
                    foreach my $b_name ( @b_names ){
                        warn join("\t", $a_name, $b_name, ), "\n";
                    }
                }
            } @{$targets_for->{ $target_id }};
    }
}

warn Dumper( %{$crispr_pairs_for} ) if $options{debug} > 1;

# sort pairs by paired off_targets and single off_targets and output info
my @header_columns = ( qw{
    pair_target_name pair_name
    number_paired_off_target_hits combined_score deletion_size
    target_1_id target_1_name target_1_assembly target_1_chr target_1_start
    target_1_end target_1_strand target_1_species target_1_requires_enzyme
    target_1_gene_id target_1_gene_name target_1_requestor target_1_ensembl_version target_1_designed
    crRNA_1_name crRNA_1_chr crRNA_1_start crRNA_1_end crRNA_1_strand
    crRNA_1_score crRNA_1_sequence crRNA_1_oligo1 crRNA_1_oligo2 crRNA_1_off_target_score
    crRNA_1_off_target_counts crRNA_1_off_target_hits crRNA_1_coding_score
    crRNA_1_coding_scores_by_transcript crRNA_1_five_prime_Gs crRNA_1_plasmid_backbone crRNA_1_GC_content 
    target_2_id target_2_name target_2_assembly target_2_chr target_2_start
    target_2_end target_2_strand target_2_species target_2_requires_enzyme
    target_2_gene_id target_2_gene_name target_2_requestor target_2_ensembl_version target_2_designed     
    crRNA_2_name crRNA_2_chr crRNA_2_start crRNA_2_end crRNA_2_strand
    crRNA_2_score crRNA_2_sequence crRNA_2_oligo1 crRNA_2_oligo2 crRNA_2_off_target_score
    crRNA_2_off_target_counts crRNA_2_off_target_hits crRNA_2_coding_score
    crRNA_2_coding_scores_by_transcript crRNA_2_five_prime_Gs crRNA_2_plasmid_backbone crRNA_2_GC_content
    combined_distance_from_targets five_prime_score difference_from_optimum_deletion_size } );
    
print $out_fh_1 join("\t", @header_columns, ), "\n";
print $out_fh_2 join("\t", @header_columns, ), "\n";

my @sorted_pairs;
my $primer_design_info;
foreach my $target_id ( @target_ids ){
    if( exists $crispr_pairs_for->{ $target_id } ){
        @sorted_pairs = sort { best_score_best_separation_paired_off_targets( $a, $b, $target_id ) }
                                @{$crispr_pairs_for->{ $target_id }};
        map {   my @info = $_->pair_info;
                if( $check_five_prime_score ){
                    push @info, five_prime_score( $_, $target_id );
                }
                else{
                    push @info, 'NULL';
                }
                push @info, abs($_->deletion_size - $OPT_CRISPR_SEPARATION);
                print $out_fh_1 join("\t", @info ), "\n"; } @sorted_pairs;
        
        my $pair = $sorted_pairs[0];
        
        my @top_scorer_info = $pair->pair_info;
        if( $check_five_prime_score ){
            push @top_scorer_info, five_prime_score( $pair, $target_id );
        }
        else{
            push @top_scorer_info, 'NULL';
        }
        push @top_scorer_info, abs($pair->deletion_size - $OPT_CRISPR_SEPARATION);
        print $out_fh_2 join("\t", @top_scorer_info ), "\n";
    }
    else{
        warn "NO Possible Pairs for $target_id!\n";
    }
}
close $out_fh_1;
close $out_fh_2;

exit 0;

###   SUBROUTINES   ###

# no_match
# 
#   Usage       : no_match( $targets_for, $columns, )
#   Purpose     : warn when the input type cannot be matched
#   Returns     : HashRef
#   Parameters  : Targets HashRef - HashRef
#                 Input Line      - ArrayRef
#   Throws      : 
#   Comments    : 
# 


sub no_match {
    my ( $targets_for, $columns, ) = @_;
    warn "Couldn't match input type: ", $columns->[0], "\n";
    return $targets_for;
}

# targets_from_gene
# 
#   Usage       : targets_from_gene( $targets_for, $columns, )
#   Purpose     : Return targets with crRNAs for every exon of a gene
#   Returns     : HashRef
#   Parameters  : Targets HashRef - HashRef
#                 Input Line      - ArrayRef
#   Throws      : 
#   Comments    : Warns if:   Cannot retrieve gene for the supplied gene id
#                             There are no protein coding transcripts in the gene
#                             If an exon is non-coding
#                             If the are no crispr targets sites for one of the targets
# 


sub targets_from_gene {
    my ( $targets_for, $columns, ) = @_;
    $targets_for->{ $columns->[0] } = [];
    $check_five_prime_score = 1;
    my $gene = fetch_gene( $columns );
    #my $gene =  $columns->[0] =~ m/\AENS[A-Z]*G[0-9]{11}# gene id/xms       ?   $gene_adaptor->fetch_by_stable_id( $columns->[0] )
    #    :       $columns->[0] =~ m/\ARNASEQG[0-9]{11}# rnaseq gene id/xms   ?   $rnaseq_gene_adaptor->fetch_by_stable_id( $columns->[0] )
    #    :                                                                       undef
    #    ;

    if( !$gene ){
        warn 'Could not find gene for id, ', $columns->[0], "\n";
        return $targets_for;
    }

    my @transcripts = grep { $_->biotype eq 'protein_coding' } @{ $gene->get_all_Transcripts() };
    map { warn $_->stable_id, "\n" } @transcripts if $options{debug};
    my $non_coding;
    if( !@transcripts ){
        warn "No protein coding transcripts for ", $gene->stable_id, ". Using all transcripts...\n";
        $non_coding = 1;
        @transcripts = @{ $gene->get_all_Transcripts() };
    }
    
    # get targets
    my %exons_seen;
    foreach my $transcript ( @transcripts ){
        foreach my $exon ( @{ $transcript->get_all_Exons() } ){
            if( exists $exons_seen{ $exon->stable_id } ){
                next;
            }
            else{
                $exons_seen{ $exon->stable_id } = 1;
            }
            # skip exons which are non-coding unless whole transcript is non-coding
            if( !$exon->coding_region_start( $transcript ) ) {
                if( !$non_coding ){
                    warn 'Exon ', $exon->stable_id, ' is non coding in transcript ' , $transcript->stable_id, "\n";
                    next;
                }
            }
            my $targets = make_targets_and_fetch_crRNAs(
                $exon->seq_region_name, $exon->seq_region_start, $exon->seq_region_end,
                $exon->seq_region_strand, $exon->stable_id, $gene, $columns->[1],
            );
            # check that there are crisprs for both the a and b targets
            # otherwise add to targets under target_id
            if( !@{$targets->[0]->crRNAs} || !@{$targets->[1]->crRNAs} ){
                warn join(q{ }, '##', $columns->[0], ': NO crRNAs for one of', $targets->[0]->target_name, 'and', $targets->[1]->target_name, ), ".\n";
                $crispr_design->remove_target( $targets->[0] );
                $crispr_design->remove_target( $targets->[1] );
            }
            else{
                push @{$targets_for->{ $columns->[0] }}, $targets;
            }
        }
    }
    if( @{$targets_for->{ $columns->[0] }} ){
        push @target_ids, $columns->[0];
    }
    return $targets_for;
}

sub fetch_gene {
    my ( $columns, ) = @_;
    my $gene =  $columns->[0] =~ m/\AENS[A-Z]*G[0-9]{11}# gene id/xms       ?   $gene_adaptor->fetch_by_stable_id( $columns->[0] )
        :       $columns->[0] =~ m/\ARNASEQG[0-9]{11}# rnaseq gene id/xms   ?   $rnaseq_gene_adaptor->fetch_by_stable_id( $columns->[0] )
        :                                                                       undef
        ;
    return $gene;
}

# targets_from_transcript
# 
#   Usage       : targets_from_transcript( $targets_for, $columns, )
#   Purpose     : Return targets with crRNAs for every exon of a transcript
#   Returns     : HashRef
#   Parameters  : Targets HashRef - HashRef
#                 Input Line      - ArrayRef
#   Throws      : 
#   Comments    : Warns if:   Cannot retrieve transcript for the supplied transcript id
#                             If the are no crispr targets sites for one of the targets
# 


sub targets_from_transcript {
    my ( $targets_for, $columns, ) = @_;
    $targets_for->{ $columns->[0] } = [];
    $check_five_prime_score = 1;
    
    my $transcript =    $columns->[0] =~ m/\AENS[A-Z]*T[0-9]{11}# transcript id/xms   ?   $transcript_adaptor->fetch_by_stable_id( $columns->[0] )
        :               $columns->[0] =~ m/\ARNASEQT[0-9]{11}# transcript id/xms      ?   $rnaseq_transcript_adaptor->fetch_by_stable_id( $columns->[0] )
        :                                                                                  undef
        ;
    if( !$transcript ){
        warn 'Could not find transcript for id, ', $columns->[0], "\n";
        return $targets_for;
    }
    my $gene = $gene_adaptor->fetch_by_transcript_stable_id( $columns->[0] );
    
    # get targets
    foreach my $exon ( @{ $transcript->get_all_Exons() } ){
        my $targets = make_targets_and_fetch_crRNAs(
            $exon->seq_region_name, $exon->seq_region_start, $exon->seq_region_end,
            $exon->seq_region_strand, $exon->stable_id, $gene, $columns->[1],
        );
        # check that there are crisprs for both the a and b targets
        # otherwise add to targets under target_id
        if( !@{$targets->[0]->crRNAs} || !@{$targets->[1]->crRNAs} ){
            warn join(q{ }, '##', $columns->[0], ': NO crRNAs for one of', $targets->[0]->target_name, 'and', $targets->[1]->target_name, ), ".\n";
            $crispr_design->remove_target( $targets->[0] );
            $crispr_design->remove_target( $targets->[1] );
        }
        else{
            push @{$targets_for->{ $columns->[0] }}, $targets;
        }
    }
    if( @{$targets_for->{ $columns->[0] }} ){
        push @target_ids, $columns->[0];
    }
    return $targets_for;
}

# targets_from_exon
# 
#   Usage       : targets_from_exon( $targets_for, $columns, )
#   Purpose     : Return targets with crRNAs for an exon
#   Returns     : HashRef
#   Parameters  : Targets HashRef - HashRef
#                 Input Line      - ArrayRef
#   Throws      : 
#   Comments    : Warns if:   Cannot retrieve exon for the supplied exon id
#                             If the are no crispr targets sites for one of the targets
# 


sub targets_from_exon {
    my ( $targets_for, $columns, ) = @_;
    $targets_for->{ $columns->[0] } = [];
    
    my $exon = $exon_adaptor->fetch_by_stable_id( $columns->[0] );
    my $gene = $gene_adaptor->fetch_by_exon_stable_id( $columns->[0] );
    
    if( !$exon ){
        warn 'Could not find exon for id, ', $columns->[0], "\n";
        return $targets_for;
    }
    # get targets
    my $targets = make_targets_and_fetch_crRNAs(
        $exon->seq_region_name, $exon->seq_region_start, $exon->seq_region_end,
        $exon->seq_region_strand, $columns->[0], $gene, $columns->[1],
    );
    # check that there are crisprs for both the a and b targets
    # otherwise add to targets under target_id
    if( !@{$targets->[0]->crRNAs} || !@{$targets->[1]->crRNAs} ){
        warn join(q{ }, '##', $columns->[0], ': NO crRNAs for one of', $targets->[0]->target_name, 'and', $targets->[1]->target_name, ), ".\n";
        $crispr_design->remove_target( $targets->[0] );
        $crispr_design->remove_target( $targets->[1] );
    }
    else{
        push @{$targets_for->{ $columns->[0] }}, $targets;
        push @target_ids, $columns->[0];
    }
    return $targets_for;
}

#targets_from_posn
#
#  Usage       : targets_from_posn( $targets_for, $columns, )
#  Purpose     : Return targets with crRNAs for a genomic region
#  Returns     : HashRef
#  Parameters  : Targets HashRef - HashRef
#                Input Line      - ArrayRef
#  Throws      : 
#  Comments    : Warns if:   Position is not in the right format. CHR:START[-END:STRAND]
#                            If the are no crispr targets sites for one of the targets
#


sub targets_from_posn {
    my ( $targets_for, $columns, ) = @_;
    $targets_for->{ $columns->[0] } = [];
    
    # split posn information
    my ( $chr, $region, $strand ) = split /:/, $columns->[0];
    if( !$chr || !$region ){
        die "Could not parse position info!\n",
            $columns->[0], "\n";
    }
    $strand = $strand   ?   $strand : '1';
    my ( $start, $end ) = split /-/, $region;
    # fetch gene by gene_id
    my $gene;
    if( $columns->[2] && $columns->[2] =~ m/\AENS[A-Z]*G[0-9]{11}/xms ){
        $gene = $gene_adaptor->fetch_by_stable_id( $columns->[2] );
    }
    
    # get targets
    my $targets = make_targets_and_fetch_crRNAs( $chr, $start, $end, $strand, $columns->[0], $gene, $columns->[1], );
    # check that there are crisprs for both the a and b targets
    # otherwise add to targets under target_id
    if( !@{$targets->[0]->crRNAs} || !@{$targets->[1]->crRNAs} ){
        warn join(q{ }, '##', $columns->[0], ': NO crRNAs for one of', $targets->[0]->target_name, 'and', $targets->[1]->target_name, ), ".\n";
        $crispr_design->remove_target( $targets->[0] );
        $crispr_design->remove_target( $targets->[1] );
    }
    else{
        push @{$targets_for->{ $columns->[0] }}, $targets;
        push @target_ids, $columns->[0];
    }
    return $targets_for;
}

# make_targets_and_fetch_crRNAs
# 
#   Usage       : make_targets_and_fetch_crRNAs( $chr, $start, $end, $strand, $target_id, $gene, $requestor, )
#   Purpose     : Creates two targets (a and b) for a feature
#                 Finds all crRNAs for each target
#                 crRNAs are filtered by strand so that the first crispr in the pair is on the reverse strand
#   Returns     : ArrayRef of Crispr::Targets
#   Parameters  : CHR         - Str
#                 START       - Int
#                 END         - Int
#                 STRAND      - Str
#                 TARGET_ID   - Str
#                 GENE        - Bio::EnsEMBL::Gene OPTIONAL
#                 REQUESTOR   - Str
#   Throws      : 
#   Comments    : 
# 


sub make_targets_and_fetch_crRNAs {
    my ( $chr, $start, $end, $strand, $target_id, $gene, $requestor, ) = @_;
    
    my $gene_id =   $gene   ?   $gene->stable_id :  undef;
    my $gene_name = $gene   ?   $gene->external_name    :  undef;
    
    my $a_target = Crispr::Target->new(
        target_name => $target_id . '_del_a',
        assembly => $options{assembly},
        chr => $chr,
        start => $start,
        end => $end,
        strand => $strand,
        species => $options{species},
        gene_id => $gene_id,
        gene_name => $gene_name,
        requestor => $requestor,
        ensembl_version => $ensembl_version,
        requires_enzyme => 0,
    );
    
    my $b_target = Crispr::Target->new(
        target_name => $target_id . '_del_b',
        assembly => $options{assembly},
        chr => $chr,
        start => $start,
        end => $end,
        strand => $strand,
        species => $options{species},
        gene_id => $gene_id,
        gene_name => $gene_name,
        requestor => $requestor,
        ensembl_version => $ensembl_version,
        requires_enzyme => 0,
    );
    print "Getting crRNAs...\n" if $options{verbose};
    foreach my $target ( $a_target, $b_target ){
        $crispr_design->find_crRNAs_by_target( $target, $options{target_sequence} );
    }
    
    if( $options{debug} ){
        warn "crRNAs:\n";
        foreach my $target ( $a_target, $b_target ){
            warn join("\t", $target->info, ), "\n";
            if( @{$target->crRNAs} ){
                map {warn $_->name, "\n";} @{$target->crRNAs};
            }
            else{
                warn $target->target_name, ": NO crRNAs.\n";
            }
        }
    }
    
    # five prime crRNA must be antisense, three prime one must be sense
    print "Filtering crRNAs...\n" if $options{verbose};
    $crispr_design->filter_crRNAs_from_target_by_strand( $a_target, '-1' );
    $crispr_design->filter_crRNAs_from_target_by_strand( $b_target, '1' );
    
    if( $options{debug} ){
        warn "Filtered crRNAs:\n";
        foreach my $target ( $a_target, $b_target ){
            warn join("\t", $target->info, ), "\n";
            if( @{$target->crRNAs} ){
                map {warn $_->name, "\n";} @{$target->crRNAs};
            }
            else{
                warn $target->target_name, ": NO crRNAs.\n";
            }
        }
    }
    
    return [ $a_target, $b_target ];
}

# best_score_best_separation
# 
#   Usage       : best_score_best_separation( $targets_for, $columns, )
#   Purpose     : sorting subroutine.
#                 Sorts by combined off target score and then difference from optimal crispr separation
#   Returns     : Int
#   Parameters  : crRNA1 to be sorted
#                 crRNA2 to be sorted
#   Throws      : 
#   Comments    : 
# 


sub best_score_best_separation {
    my ( $a, $b, ) = @_;
    my $a_separation = abs($a->deletion_size - $OPT_CRISPR_SEPARATION);
    my $b_separation = abs($b->deletion_size - $OPT_CRISPR_SEPARATION);
    
	return (
        $b->combined_single_off_target_score <=>
            $a->combined_single_off_target_score ||
        $a_separation <=> $b_separation );
}

# best_score_best_separation_paired_off_targets
# 
#   Usage       : best_score_best_separation_paired_off_targets( $targets_for, $columns, )
#   Purpose     : sorting subroutine.
#                 Sorts by combined score and then difference from optimal crispr separation
#                 combined score includes five prime score if $check_five_prime_score is set.
#   Returns     : Int
#   Parameters  : crRNA1 to be sorted
#                 crRNA2 to be sorted
#   Throws      : 
#   Comments    : 
# 
# 

# sort pairs by paired off_targets and single off_targets and output info
sub best_score_best_separation_paired_off_targets {
    my ( $a, $b, $target_id ) = @_;
    my $a_separation = abs($a->deletion_size - $OPT_CRISPR_SEPARATION);
    my $b_separation = abs($b->deletion_size - $OPT_CRISPR_SEPARATION);
    
    my ( $a_score, $b_score );
    if( $check_five_prime_score ){
        my $five_prime_score_a = five_prime_score( $a, $target_id );
        my $five_prime_score_b = five_prime_score( $b, $target_id );
        $a_score = $a->combined_single_off_target_score * $five_prime_score_a;
        $b_score = $b->combined_single_off_target_score * $five_prime_score_b;
    }
    else{
        $a_score = $a->combined_single_off_target_score;
        $b_score = $b->combined_single_off_target_score;
    }

	return ( $a->paired_off_targets <=> $b->paired_off_targets ||
                $b_score <=> $a_score ||
                $a_separation <=> $b_separation );
}

# cut_site
# 
#   Usage       : cut_site( $targets_for, $columns, )
#   Purpose     : Returns the cut-site position for a crispr position
#   Returns     : Int
#   Parameters  : START   - Int
#                 END     - Int
#                 STRAND  - Str
#   Throws      : 
#   Comments    : 
# 
# 

sub cut_site {
    my ( $start, $end, $strand ) = @_;
    return $strand eq '1'       ?   $end - 6    : $start + 5;
}

# five_prime_score
# 
#   Usage       : five_prime_score( $targets_for, $columns, )
#   Purpose     : Returns the average five prime score for a crispr pair and target
#   Returns     : Int (0-1)
#   Parameters  : CrisprPair      - Crispr::CrisprPair
#                 Target id       - Str
#   Throws      : 
#   Comments    : 
# 
# 

sub five_prime_score {
    my ( $cr_pair, $target_id ) = @_;

    my $transcript;
    if( $target_id =~ m/\AENS[A-Z]*E[0-9]{11}\z/xms ){
        my @canonical_transcript = grep { $_->is_canonical } @{ $transcript_adaptor->fetch_all_by_exon_stable_id( $target_id ) };
        if( scalar @canonical_transcript == 1 ){
            $transcript = $canonical_transcript[0];
        }
        my $cut_site = $transcript->seq_region_strand eq '1' ?
            $cr_pair->crRNA_1->cut_site :  $cr_pair->crRNA_2->cut_site;
        return calc_five_prime_score( $cut_site, $transcript );
    }
    elsif( $target_id =~ m/\AENS[A-Z]*T[0-9]{11}\z/xms ){
        $transcript = $transcript_adaptor->fetch_by_stable_id( $target_id );
        my $cut_site = $transcript->seq_region_strand eq '1' ?
            $cr_pair->crRNA_1->cut_site :  $cr_pair->crRNA_2->cut_site;
        return calc_five_prime_score( $cut_site, $transcript );
    }
    elsif( $target_id =~ m/\AENS[A-Z]*G[0-9]{11}\z/xms ){
        my $gene = $gene_adaptor->fetch_by_stable_id( $target_id );
        my @transcripts = grep { $_->biotype eq 'protein_coding' } @{ $gene->get_all_Transcripts };
        my $trans_count = 0;
        my $five_prime_total = 0;
        if( !@transcripts ){
            return 0;
        }
        foreach ( @transcripts ){
            $trans_count++;
            my $cut_site = $_->seq_region_strand eq '1' ?
                $cr_pair->crRNA_1->cut_site :  $cr_pair->crRNA_2->cut_site;
            $five_prime_total += calc_five_prime_score( $cut_site, $_ );
        }
        return $five_prime_total/$trans_count;
    }
}

# calc_five_prime_score
# 
#   Usage       : calc_five_prime_score( $targets_for, $columns, )
#   Purpose     : Calculates the five prime score for a position and a transcript
#   Returns     : Int (0-1)
#   Parameters  : Cut site    - Int
#                 transcript  -   Bio::EnsEMBL::Transcript
#   Throws      : 
#   Comments    : 
# 
# 

sub calc_five_prime_score {
    my ( $cut_site, $transcript ) = @_;
    return 0 if !$transcript;
    my $translation = $transcript->translation();
    return 0 if !$translation;
    # Length
    my $translation_length = $translation->length;
    
    # Position in translation
    my $translation_pos;
    #my $new_transcript = $transcript_adaptor->fetch_by_stable_id($transcript->stable_id);
    my @coords = $transcript->genomic2pep($cut_site, $cut_site, $transcript->strand());
    foreach my $coord (@coords) {
        #print Dumper( $coord );
        next if !$coord->isa('Bio::EnsEMBL::Mapper::Coordinate');
        $translation_pos = $coord->start;
    }
    if (!$translation_pos) {
        #warn "No translation position!\n";
        return 0;
    }
    elsif( $translation_pos < 25 ){
        return 0;
    }
    else{
        return 1 - ($translation_pos / $translation_length);
    }
}

# get_and_check_options
# 
#   Usage       : get_and_check_options()
#   Purpose     : Gets the options from the command line and places in the %options HASH
#   Returns     : None
#   Parameters  : None
#   Throws      : If neither of --target_genome or --species is set
#                 If --num_five_prime_Gs is not 0, 1 OR 2
#                 If --target_sequence is not 23 bp long # could change for non S.pyogenes Cas9
#                 If --target_sequence and --num_five_prime_Gs options are incompatible
#   Comments    : 
# 
# 

sub get_and_check_options {
    
    GetOptions(
        \%options,
        'registry_file=s',
        'species=s',
        'assembly=s',
        'target_genome=s',
        'annotation_file=s',
        'variation_file=s',
        'target_sequence=s',
        'num_five_prime_Gs=i',
        'min_crispr_separation=i',
        'max_crispr_separation=i',
        'opt_crispr_separation=i',
        'max_off_target_separation=i',
        'file_base=s',
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
    
    if( !$options{target_genome} && $options{species} ){
        $options{target_genome} = $options{species} eq 'zebrafish'    ?  '/lustre/scratch110/sanger/rw4/genomes/Dr/Zv9/striped/zv9_toplevel_unmasked.fa'
            :               $options{species} eq 'mouse'     ?   '/lustre/scratch110/sanger/rw4/genomes/Mm/e70/striped/Mus_musculus.GRCm38.70.dna.noPATCH.fa'
            :               $options{species} eq 'human'     ?   '/lustre/scratch110/sanger/rw4/genomes/Hs/GRCh37_70/striped/Homo_sapiens.GRCh37.70.dna.noPATCH.fa'
            :                                           undef
        ;
    }
    elsif( $options{target_genome} && !$options{species} ){
        $options{species} = $options{target_genome} eq '/lustre/scratch110/sanger/rw4/genomes/Dr/Zv9/striped/zv9_toplevel_unmasked.fa'     ?   'zebrafish'
        :           $options{target_genome} eq '/lustre/scratch110/sanger/rw4/genomes/Mm/e70/striped/Mus_musculus.GRCm38.70.dna.noPATCH.fa'      ?   'mouse'
        :           $options{target_genome} eq '/lustre/scratch110/sanger/rw4/genomes/Hs/GRCh37_70/striped/Homo_sapiens.GRCh37.70.dna.noPATCH.fa'    ? 'human'
        :                                                                                                                     undef
        ;
    }
    elsif( !$options{target_genome} && !$options{species} ){
        pod2usage( "Must specify at least one of --target_genome and --species!\n." );
    }
    
    # check annotation file and variation file exist
    foreach my $file ( $options{annotation_file}, $options{variation_file} ){
        if( $file ){
            if( !-e $file || -z $file ){
                die "$file does not exists or is empty!\n";
            }
        }
    }
    
    if( defined $options{num_five_prime_Gs} ){
        Readonly::Array my @NUM_G_OPTIONS => ( 0, 1, 2 );
        if( none { $_ == $options{num_five_prime_Gs} } @NUM_G_OPTIONS ){
            pod2usage("option --num_five_prime_Gs must be one of 0, 1 or 2!\n");
        }
    }
    
    my $five_prime_Gs_in_target_seq;
    if( $options{target_sequence} ){
        # check target sequence is 23 bases long
        if( length $options{target_sequence} != 23 ){
            pod2usage("Target sequence must be 23 bases long!\n");
        }
        $options{target_sequence} =~ m/\A(G*) # match any Gs at the start/xms;
        $five_prime_Gs_in_target_seq = length $1;
        
        if( defined $options{num_five_prime_Gs} ){
            if( $five_prime_Gs_in_target_seq != $options{num_five_prime_Gs} ){
                pod2usage("The number of five prime Gs in target sequence, ",
                          $options{target_sequence}, " doesn't match with the value of --num_five_prime_Gs option, ",
                          $options{num_five_prime_Gs}, "!\n");
            }
        }
        else{
            $options{num_five_prime_Gs} = $five_prime_Gs_in_target_seq;
        }
    }
    else{
        if( defined $options{num_five_prime_Gs} ){
            my $target_seq = 'NNNNNNNNNNNNNNNNNNNNNGG';
            my $Gs = q{};
            for ( my $i = 0; $i < $options{num_five_prime_Gs}; $i++ ){
                $Gs .= 'G';
            }
            substr( $target_seq, 0, $options{num_five_prime_Gs}, $Gs );
            #print join("\t", $Gs, $target_seq ), "\n";
            $options{target_sequence} = $target_seq;
        }
        else{
            $options{target_sequence} = 'GGNNNNNNNNNNNNNNNNNNNGG';
            $options{num_five_prime_Gs} = 2;
        }
    }
    
    $options{debug} = 0 if !$options{debug};
    
    print "Settings:\n", map { join(' - ', $_, defined $options{$_} ? $options{$_} : 'off'),"\n" } sort keys %options if $options{verbose};
}

__END__

=pod

=head1 NAME

crispr_pairs_for_deletions.pl

=head1 DESCRIPTION

Design crispr pairs to create deletions.

=head1 SYNOPSIS

    crispr_pairs_for_deletions.pl [options] filename(s) | target info on STDIN
        --registry_file                 a registry file for connecting to the Ensembl database
        --species                       species for the targets
        --assembly                      current assembly
        --target_genome                 a target genome fasta file for scoring off-targets
        --annotation_file               an annotation gff file for scoring off-targets
        --variation_file                a file of known background variation for filtering crispr target sites
        --target_sequence               crRNA consensus sequence (e.g. GGNNNNNNNNNNNNNNNNNNNGG)
        --num_five_prime_Gs             The number of 5' Gs present in the consensus sequence, 0,1 OR 2
        --min_crispr_separation         The minimum separation for two crispr sites in a pair [default=20 bp]
        --max_crispr_separation         The maximum separation for two crispr sites in a pair [default=60 bp]
        --opt_crispr_separation         The optimum separation for two crispr sites in a pair
        --max_off_target_separation     window size to search for paired off-target hits [default=10000 bp]
        --file_base                     a prefix for all output files
        --help                          prints help message and exits
        --man                           prints manual page and exits
        --debug                         prints debugging information
        --verbose                       prints logging information


=head1 ARGUMENTS

=over

=item B<input>

A list of filenames or input on STDIN containing target info.

=over

=item Target info: Tab-separated  TARGET_ID   REQUESTOR   [GENE_ID]

=item Accepted types of target ids are:

=back

=over

=item GENE_IDS:         Ensembl gene ids. Either ENS*G, LRG or RNASEQG

=item TRANSCRIPT_IDS:   Ensembl transcript ids. Either ENS*T or RNASEQT

=item EXON_IDS:         Ensembl gene ids. ENS*E.

=item POSN:             Region of genome. CHR:START-END[:STRAND]

=back

=back

=head1 OPTIONS

=over

=item B<--registry_file>

A registry file for connecting to the Ensembl database.
Connects anonymously if registry file is not supplied.

=item B<--species >

The relevant species for the supplied targets.

=item B<--assembly >

The version of the genome assembly.

=item B<--target_genome >

The path of the target genome file. This needs to have been indexed by bwa in order to score crispr off-targets.

=item B<--annotation_file >

The path of the annotation file for the appropriate species. Must be in gff format.

=item B<--variation_file >

A file of known background variation for filtering crispr target sites.
Accepts tabixed vcf and all_var format.

=item B<--target_sequence >

The Cas9 target sequence [default: NNNNNNNNNNNNNNNNNNNNNGG ]
This sequence must match the --num_five_prime_Gs option if set.

=item B<--num_five_prime_Gs >

The numbers of Gs required at the 5' end of the target sequence.
e.g. 1 five prime G has a target sequence GNNNNNNNNNNNNNNNNNNNNGG. [default: 0]
Must be compatible with --target_sequence if set.

=item B<--min_crispr_separation >

The minimum required separation for two crispr sites to be eligible as a crispr pair [default:30].
This is measured as the distance between the two predicted cut sites.
i.e. a pair of crispr sites with a separation of 34bp lie exactly adjacent to each other as shown below.

            |<------------ 34bp ------------>|   PAM
                             ----------------|----->
AGCATGCCGTAGACGACTAGACACGATACAGACGTTAGAGAGTAGACGAAGGGACACG
      <-----|----------------                 
      PAM

=item B<--max_crispr_separation >

The maximum allowed separation for two crispr sites to be eligible as a crispr pair [default: 60].
Separation is defined above.

=item B<--opt_crispr_separation >

The optimum separation for the two crispr sites in a crispr pair.
If no optimum separation is set, it defaults to half-way between the min and max (i.e. min + (max - min)/2 ).
With the default settings for min and max this would be 45 bp.
Separation is defined above.

=item B<--max_off_target_separation >

The window size for searching for pairs of off-target sites [default: 10000 (10kb)]

=item B<--file_base >

A prefix for all output files. This is added to output filenames with a '_' as separator.

=item B<--debug>

Print debugging information.

=item B<--verbose>

Switch to verbose output mode

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

=cut
