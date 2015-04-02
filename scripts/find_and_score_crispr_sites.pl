#!/usr/bin/env perl
use warnings; use strict;
# use MODULES
use autodie;
use Getopt::Long;
use Pod::Usage;
use Readonly;
use List::MoreUtils qw( none );

use Bio::EnsEMBL::Registry;
use Bio::Seq;
use Bio::SeqIO;

use Data::Dumper;
use English qw( -no_match_vars );

use Crispr::Target;
use Crispr::crRNA;
use Crispr;

# option variables
my %options;
get_and_check_options();

#get current date
use DateTime;
my $date_obj = DateTime->now();
my $todays_date = $date_obj->ymd;

# check registry file
if( $options{registry_file} ){
    Bio::EnsEMBL::Registry->load_all( $options{registry_file} );
}
else{
    # if no registry file connect anonymously to the public server
    Bio::EnsEMBL::Registry->load_registry_from_db(
      -host    => 'ensembldb.ensembl.org',
      -user    => 'anonymous',
    );
}
my $ensembl_version = Bio::EnsEMBL::ApiVersion::software_version();

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

# open filehandles for off_target fasta files
my $basename = $todays_date;
$basename =~ s/\A/$options{file_base}_/xms if( $options{file_base} );

# make new design object
my $crispr_design = Crispr->new(
    species => $options{species},
    target_seq => $options{target_sequence},
    target_genome => $options{target_genome},
    annotation_file => $options{annotation_file},
    slice_adaptor => $slice_adaptor,
    debug => $options{debug},
);
if( defined $options{num_five_prime_Gs} ){
    $crispr_design->five_prime_Gs( $options{num_five_prime_Gs} );
}

print "Reading input...\n" if $options{verbose};
while(<>){
    chomp;
    s/,//xmsg;
    
    my $rv;
    my @columns = split /\t/xms;
    # guess id type
    $rv =   $columns[0] =~ m/\AENS[A-Z]*G[0-9]{11}  # gene id/xms               ?   get_gene( @columns )
        :   $columns[0] =~ m/\ALRG_[0-9]+/xms                                   ?   get_gene( @columns )
        :   $columns[0] =~ m/\ARNASEQG[0-9]{11} # RNA Seq gene id/xms           ?   get_gene( @columns )
        :   $columns[0] =~ m/\AENS[A-Z]*E[0-9]{11}  # exon id/xms               ?   get_exon( @columns )
        :   $columns[0] =~ m/\AENS[A-Z]*T[0-9]{11}  # transcript id/xms         ?   get_transcript( @columns )
        :   $columns[0] =~ m/\ARNASEQT[0-9]{11} # RNA Seq transcript id/xms     ?   get_transcript( @columns )
        :   $columns[0] =~ m/\A[\w.]+:\d+\-\d+[:0-1-]*# position/xms            ?   get_posn( @columns )
        :                                                                       "Couldn't match input type: " . join("\t", @columns,) . ".\n";
        ;
    
    if( $rv =~ m/\ACouldn't\smatch/xms ){
        die $rv;
    }
    if( $rv == 0 ){
        warn "No crRNAs for ", $columns[0], ".\n";
    }
}

if( !@{ $crispr_design->targets } ){
    die "No Targets!\n";
}

if( $options{debug} ){
    map {   print join("\t", $_->name, $_->gene_id, );
            if( $_->crRNAs){ print "\t", scalar @{$_->crRNAs} } print "\n"
        } @{$crispr_design->targets};
}

# score crRNAs
if( $options{no_crRNA} ){
    print "Skipping Scoring Off-Targets...\n" if $options{verbose};    
    print "Skipping Scoring Coding scores...\n" if $options{verbose};    
}
else{
    foreach my $target ( @{ $crispr_design->targets } ){
        # filter for variation if option selected
        if( defined $options{variation_file} ){
            $crispr_design->filter_crRNAs_from_target_by_snps_and_indels( $target, $options{variation_file}, 1 );
        }
        if( !@{$target->crRNAs} ){
            #remove from targets if there are no crispr sites for that target
            warn "No crRNAs for ", $target->target_name, " after filtering by variation\n";
            $crispr_design->remove_target( $target );
        }
    }
    
    print "Scoring Off-Targets...\n" if $options{verbose};
    $crispr_design->find_off_targets( $crispr_design->all_crisprs, $basename, );
    
    if( $options{coding} ){
        print "Calculating coding scores...\n" if $options{verbose};
        foreach my $target ( @{ $crispr_design->targets } ){
            foreach my $crRNA ( @{$target->crRNAs} ){
                if( $crRNA->target && $crRNA->target_gene_id ){
                    my $transcripts;
                    my $gene_id = $crRNA->target_gene_id;
                    my $gene = $gene_adaptor->fetch_by_stable_id( $gene_id );
                    if( !$gene ){
                        next;
                    }
                    $transcripts = $gene->get_all_Transcripts;
                    $crRNA = $crispr_design->calculate_all_pc_coding_scores( $crRNA, $transcripts );
                }
            }
        }
    }
}

print "Outputting results...\n" if $options{verbose};
Readonly my @columns => (
    qw{ target_id target_name assembly chr start end strand
        species requires_enzyme gene_id gene_name requestor ensembl_version
        designed crRNA_name chr start end strand score sequence oligo1 oligo2
        off_target_score off_target_counts off_target_hits
        coding_score coding_scores_by_transcript five_prime_Gs plasmid_backbone
        GC_content notes }
);

if( $options{no_crRNA} ){
    print '#', join("\t", @columns[0..13] ), "\n";
}
else{
    print join("\t", @columns ), "\n";    
}
foreach my $target ( @{ $crispr_design->targets } ){
    if( $options{no_crRNA} ){
        print join("\t", $target->info ), "\n";
    }
    else{
        foreach my $crRNA ( sort { $b->score <=> $a->score } @{$target->crRNAs} ){        
            # output
            print join("\t",
                $crRNA->target_info_plus_crRNA_info,
            ), "\t";
            
            my @notes;
            # check composition
            my $base_composition = $crRNA->base_composition;
            my $not_ideal;
            foreach my $base ( qw{ A C G T } ){
                if( $base_composition->{$base} < 0.1 || $base_composition->{$base} > 0.4 ){
                    $not_ideal = 1;
                }
            }
            if( $not_ideal ){
                push @notes, "Base Composition is not ideal!";
            }
            
            # check GC content
            if( $base_composition->{C} + $base_composition->{G} < 0.4 ){
                push @notes, "GC content less than 40%!";
            }
            
            # check pre-PAM base
            my $pre_pam_base = substr($crRNA->sequence, 19, 1);
            if( $pre_pam_base eq 'G' ){
                push @notes, "base20 is a G";
            }
            print join(';', @notes, ), "\n";
        }
    }
}

###   SUBROUTINES   ###

# get_exon
# 
#   Usage       : get_exon( $exon_id, $requestor )
#   Purpose     : make a target for the supplied exon and find crispr target sites
#   Returns     : 1 if successful, 0 otherwise.
#   Parameters  : Exon id     - Str
#                 Requestor   - Str     OPTIONAL
#   Throws      : If there is an unexpected error generated by find_crRNAs_by_target
#   Comments    : 
# 
# 

sub get_exon {
    my ( $exon_id, $requestor ) = @_;
    my $success = 0;
    $requestor = get_requestor( $requestor );
    $requestor =~ s/'//xmsg;
    # get exon object
    my $exon = $exon_adaptor->fetch_by_stable_id( $exon_id );
    my ( $chr, $gene, );
    if( $exon ){
        $chr = $exon->seq_region_name;
        # get gene id and transcripts
        $gene = $gene_adaptor->fetch_by_exon_stable_id( $exon_id );
        my $target = Crispr::Target->new(
            target_name => $exon_id,
            assembly => $options{assembly},
            chr => $chr,
            start => $exon->seq_region_start,
            end => $exon->seq_region_end,
            strand => $exon->seq_region_strand,
            species => $options{species},
            gene_id => $gene->stable_id,
            gene_name => $gene->external_name,
            requestor => $requestor,
            ensembl_version => $ensembl_version,
        );
        
        if( $options{enzyme} ){
            $target->requires_enzyme( $options{enzyme} );
        }
        
        if( $options{no_crRNA} ){
            $crispr_design->add_target( $target );
        }
        else{
            my $crRNAs = [];
            eval{
                $crRNAs = $crispr_design->find_crRNAs_by_target( $target, );
            };
            if( $EVAL_ERROR && $EVAL_ERROR =~ m/seen/xms ){
                $success = 1;
                warn join(q{ }, $EVAL_ERROR, "Skipping...\n", );
                next;
            }
            elsif( $EVAL_ERROR ){
                die $EVAL_ERROR;
            }
            if( scalar @{$crRNAs} ){
                $success = 1;
            }
            else{
                warn "No crRNAs for ", $target->target_name, "\n";
                $crispr_design->remove_target( $target );
            }
        }
    }
    else{
        warn "Couldn't get exon for id:$exon_id.\n";
        $success = 1;
    }
    return $success;
}

# get_gene
# 
#   Usage       : get_gene( $gene_id, $requestor )
#   Purpose     : make a target for each of the exons of the supplied gene and find crispr target sites
#   Returns     : 1 if successful, 0 otherwise.
#   Parameters  : Gene id     - Str
#                 Requestor   - Str     OPTIONAL
#   Throws      : If there is an unexpected error generated by find_crRNAs_by_target
#   Comments    : 
# 
# 

sub get_gene {
    my ( $gene_id, $requestor ) = @_;
    my $success = 0;
    $requestor = get_requestor( $requestor );
    $requestor =~ s/'//xmsg;
    #get gene
    my $gene =  $gene_id =~ m/\AENS[A-Z]*G[0-9]{11}# gene id/xms       ?   $gene_adaptor->fetch_by_stable_id( $gene_id )
        :       $gene_id =~ m/\ARNASEQG[0-9]{11}# rnaseq gene id/xms   ?   $rnaseq_gene_adaptor->fetch_by_stable_id( $gene_id )
        :                                                                  undef
        ;
    
    if( $gene ){
        # check for LRG_genes
        if( $gene->biotype eq 'LRG_gene' ){
            # get corresponding non-LRG gene
            my $genes = $gene_adaptor->fetch_all_by_external_name( $gene->external_name );
            my @genes = grep { $_->stable_id !~ m/\ALRG/xms } @{$genes};
            if( scalar @genes == 1 ){
                warn join(q{ }, 'Converted LRG gene,', $gene->stable_id, 'to', $genes[0]->stable_id, ), "\n";
                $gene = $genes[0];
            }
            else{
                warn "Could not find a single corresponding gene for LRG gene, ", $gene->stable_id, " got:",
                    map { $_->stable_id } @genes,
                    "\n";
            }
        }
        # get transcripts
        my $transcripts = $gene->get_all_Transcripts();
        
        foreach my $transcript ( @{$transcripts} ){
            # check whether transcript is protein-coding
            next if( $transcript->biotype() ne 'protein_coding' );
            # get all exons
            my $exons = $transcript->get_all_Exons();
            
            foreach my $exon ( @{$exons} ){
                my $target = Crispr::Target->new(
                    target_name => $exon->stable_id,
                    assembly => $options{assembly},
                    chr => $exon->seq_region_name,
                    start => $exon->seq_region_start,
                    end => $exon->seq_region_end,
                    strand => $exon->seq_region_strand,
                    species => $options{species},
                    gene_id => $gene->stable_id,
                    gene_name => $gene->external_name,
                    requestor => $requestor,
                    ensembl_version => $ensembl_version,
                );
                
                if( $options{enzyme} ){
                    $target->requires_enzyme( $options{enzyme} );
                }
                
                if( $options{no_crRNA} ){
                    $crispr_design->add_target( $target );
                }
                else{
                    my $crRNAs = [];
                    eval{
                        $crRNAs = $crispr_design->find_crRNAs_by_target( $target, );
                    };
                    if( $EVAL_ERROR && $EVAL_ERROR =~ m/seen/xms ){
                        warn join(q{ }, $EVAL_ERROR, "Skipping...\n", );
                        next;
                    }
                    elsif( $EVAL_ERROR ){
                        die $EVAL_ERROR;
                    }
                    
                    if( scalar @{$crRNAs} ){
                        $success = 1;
                    }
                    else{
                        warn "No crRNAs for ", $target->target_name, "\n";
                        $crispr_design->remove_target( $target );
                    }
                }
            }
        }
    }
    else{
        warn "Couldn't get gene for id:$gene_id.\n";
        $success = 1;
    }
    return $success;
}

# get_transcript
# 
#   Usage       : get_transcript( $transcript_id, $requestor )
#   Purpose     : make a target for each of the exons of the supplied transcript and find crispr target sites
#   Returns     : 1 if successful, 0 otherwise.
#   Parameters  : Transcript id   - Str
#                 Requestor       - Str     OPTIONAL
#   Throws      : If there is an unexpected error generated by find_crRNAs_by_target
#   Comments    : 
# 
# 

sub get_transcript {
    my ( $transcript_id, $requestor ) = @_;
    my $success = 0;
    $requestor = get_requestor( $requestor );
    $requestor =~ s/'//xmsg;
    #get transcript
    my $transcript =    $transcript_id =~ m/\AENS[A-Z]*T[0-9]{11}# transcript id/xms   ?   $transcript_adaptor->fetch_by_stable_id( $transcript_id )
        :               $transcript_id =~ m/\ARNASEQT[0-9]{11}# transcript id/xms      ?   $rnaseq_transcript_adaptor->fetch_by_stable_id( $transcript_id )
        :                                                                                  undef
        ;
    if( $options{debug} ){
        if( $transcript ){
            warn join("\t", $transcript->stable_id, );
        }
    }
    
    if( $transcript ){
        my $gene = $transcript->get_Gene;
        my $exons = $transcript->get_all_Exons();
        
        foreach my $exon ( @{$exons} ){
            my $target = Crispr::Target->new(
                target_name => $exon->stable_id,
                assembly => $options{assembly},
                chr => $exon->seq_region_name,
                start => $exon->seq_region_start,
                end => $exon->seq_region_end,
                strand => $exon->seq_region_strand,
                species => $options{species},
                gene_id => $gene->stable_id,
                gene_name => $gene->external_name,
                requestor => $requestor,
                ensembl_version => $ensembl_version,
            );
            
            if( $options{enzyme} ){
                $target->requires_enzyme( $options{enzyme} );
            }
            
            if( $options{no_crRNA} ){
                $crispr_design->add_target( $target );
            }
            else{
                my $crRNAs = [];
                eval{
                    $crRNAs = $crispr_design->find_crRNAs_by_target( $target, );
                };
                if( $EVAL_ERROR && $EVAL_ERROR =~ m/seen/xms ){
                    warn join(q{ }, $EVAL_ERROR, "Skipping...\n", );
                    next;
                }
                elsif( $EVAL_ERROR ){
                    die $EVAL_ERROR;
                }
                if( scalar @{$crRNAs} ){
                    $success = 1;
                }
                else{
                    warn "No crRNAs for ", $target->target_name, "\n";
                    $crispr_design->remove_target( $target );
                }
            }
        }
    }
    else{
        warn "Couldn't get transcript for id:$transcript_id.\n";
        $success = 1;
    }
    return $success;
}

# get_posn
# 
#   Usage       : get_posn( $posn, $requestor $gene_id )
#   Purpose     : make a target for each of the exons of the supplied posn and find crispr target sites
#   Returns     : 1 if successful, 0 otherwise.
#   Parameters  : Genomic Position    - Str
#                 Requestor           - Str   OPTIONAL
#                 Gene id             - Str   OPTIONAL
#   Throws      : If the supplied position is not in the right format. CHR:START[-END:STRAND]
#                 If the supplied Gene id doesn't look like an Ensembl id
#                 If there is an unexpected error generated by find_crRNAs_by_target
#   Comments    : 
# 
# 

sub get_posn {
    my ( $posn, $requestor, $gene_id  ) = @_;
    my $success = 0;
    $requestor = get_requestor( $requestor );
    $requestor =~ s/'//xmsg;
    
    my ( $chr, $position, $strand, ) =  split /:/, $posn;
    if( !$chr || !$position ){
        die "Need at least a chr and position ( chr:position )\n";
    }
    my ( $start_position, $end_position );
    if( $position =~ m/-/ ){
        my @posns = split /-/, $position;
        $start_position = $posns[0];
        $end_position = $posns[1];
    }
    else{
        $start_position = $position;
        $end_position = $position;
    }
    if( !$strand ){
        $strand = 1;
    }
    my $target_name = $chr . ":" . $start_position . "-" . $end_position . ":" . $strand;
    
    # get slice for position and get genes and transcripts that overlap posn
    my $slice = $slice_adaptor->fetch_by_region( 'toplevel', $chr, $start_position, $end_position, $strand );
    
    if( $slice ){
        my $gene;
        if( $gene_id ){
            if( $gene_id !~ m/\AENS[A-Z]*G[0-9]{11}\z/xms ){
                die join(" ", $gene_id, "is not a valid gene id.", ), "\n";
            }
            # get gene from gene id and get transcripts
            $gene = $gene_adaptor->fetch_by_stable_id( $gene_id );
        }
        else{
            my $genes = $gene_adaptor->fetch_all_by_Slice( $slice );
            if( scalar @$genes == 1 ){
                $gene = $genes->[0];
            }
        }
        
        my $target = Crispr::Target->new(
            target_name => $target_name,
            assembly => $options{assembly},
            chr => $chr,
            start => $start_position,
            end => $end_position,
            strand => $strand,
            species => $options{species},
            gene_id => $gene->stable_id,
            gene_name => $gene->external_name,
            requestor => $requestor,
            ensembl_version => $ensembl_version,
        );
        
        if( $options{enzyme} ){
            $target->requires_enzyme( $options{enzyme} );
        }
        
        if( $options{no_crRNA} ){
            $crispr_design->add_target( $target );
        }
        else{
            my $crRNAs = [];
            eval{
                $crRNAs = $crispr_design->find_crRNAs_by_target( $target, );
            };
            if( $EVAL_ERROR && $EVAL_ERROR =~ m/seen/xms ){
                warn join(q{ }, $EVAL_ERROR, "Skipping...\n", );
                next;
            }
            elsif( $EVAL_ERROR ){
                die $EVAL_ERROR;
            }
            if( scalar @{$crRNAs} ){
                $success = 1;
            }
            else{
                warn "No crRNAs for ", $target->target_name, "\n";
                $crispr_design->remove_target( $target );
            }
        }
    }
    else{
        warn "Couldn't get slice for region, $target_name.\n";
        $success = 1;
    }
    return $success;
}

# get_requestor
# 
#   Usage       : get_requestor( $input )
#   Purpose     : produces a requestor from the input and options
#   Returns     : Str
#   Parameters  : Requestor   - Str
#   Throws      : 
#   Comments    : Returns the --requestor option unless it is NULL
#                 then the input supplied to the subroutine unless it is undefined
#                 then returns NULL
# 
# 

sub get_requestor {
    my ( $input, ) = @_;
    my $requestor = $options{requestor} ne 'NULL'   ?   $options{requestor}
        :           $input                          ?   $input
        :           $options{requestor};
    return $requestor;
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
        'enzyme+',
        'target_sequence=s',
        'num_five_prime_Gs=i',
        'coding',
        'file_base=s',
        'requestor=s',
        'no_crRNA',
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
        pod2usage( "Must specify at least one of --target_genome and --species!.\n" );
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
        if( none { $_ == $options{num_five_prime_Gs} } ( 0, 1, 2 ) ){
            pod2usage("option --num_five_prime_Gs must be one of 0, 1 or 2!\n");
        }
    }
    
    my $five_prime_Gs_in_target_seq;
    if( $options{target_sequence} ){
        # check target sequence is 23 bases long
        if( length $options{target_sequence} != 23 ){
            pod2usage("Target sequence must be 23 bases long!\n");
        }
        if( $options{target_sequence} =~ m/\A(G*) # match Gs at the start/xms ){
            $five_prime_Gs_in_target_seq = length $1;
        }
        else{
            $five_prime_Gs_in_target_seq = 0;
        }
        
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
            $options{target_sequence} = 'NNNNNNNNNNNNNNNNNNNNNGG';
            $options{num_five_prime_Gs} = 0;
        }
    }
    
    if( !$options{requestor} ){
        $options{requestor} = 'NULL';
    }
    $options{debug} = 0 if !$options{debug};
    
    warn "Settings:\n", map { join(' - ', $_, defined $options{$_} ? $options{$_} : 'off'),"\n" } sort keys %options if $options{verbose};
}

__END__

=pod

=head1 NAME

find_and_score_crRNAs.pl

=head1 DESCRIPTION

find_and_score_crRNAs.pl takes either an Ensembl exon id, gene id, transcript id
or a genomic position for a target and uses the Ensembl API to retrieve sequence
for the region. The region is scanned for possible crispr guideRNA targets (the
target sequence can be adjusted) and these possible crRNA targets are scored for
possible off-target effects and optionally for its position in coding transcripts.

=head1 SYNOPSIS

    find_and_score_crRNAs.pl [options] filename(s) | target info on STDIN
        --registry_file         a registry file for connecting to the Ensembl database
        --species               species for the targets
        --assembly              current assembly
        --target_genome         a target genome fasta file for scoring off-targets
        --annotation_file       an annotation gff file for scoring off-targets
        --variation_file        a file of known background variation for filtering crispr target sites
        --target_sequence       crRNA consensus sequence (e.g. GGNNNNNNNNNNNNNNNNNNNGG)
        --num_five_prime_Gs     The number of 5' Gs present in the consensus sequence, 0,1 OR 2
        --enzyme                Sets the requires_enzyme attribute of targets [default: n]
        --coding                turns on scoring of position of site within target gene
        --file_base             a prefix for all output files
        --requestor             A requestor to use for all targets
        --no_crRNA              option to supress finding and scoring crispr target sites
        --help                  prints help message and exits
        --man                   prints manual page and exits
        --debug                 prints debugging information
        --verbose               turns on verbose output

=head1 REQUIRED ARGUMENTS

=over

=item B<input>

tab-separated input.
Columns are: TARGETS    REQUESTOR   [GENE_ID]

TARGETS: Acceptable targets are Ensembl exon ids, gene ids, transcript ids or
genomic positions/regions. RNA Seq gene/transcript ids are also accepted.
All four types can be present in one file.

REQUESTOR: A requestor is required if you are using the SQL database to store guide RNAs.
Each target can have a different requestor if supplied in the input rather than by the --requestor option.

GENE_ID: Optionally an Ensembl gene id can be supplied for genomic regions.

This input can also be supplied on STDIN rather than a file.

=back

=head1 OPTIONS

=over

=item B<--registry_file>

a registry file for connecting to the Ensembl database.
If no file is supplied the script connects anonymously to the current version of the database.

=item B<--species >

The relevant species for the supplied targets e.g mouse. [default: zebrafish]

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

=item B<--enzyme>

switch to indicate if a unique restriction site is required within the crispr site.
This option doesn't affect crispr selection or scoring. The output is modified
to indicate that this target needs a restriction site for screening. This will
then affect the behaviour of scripts used to design screening primers.

=item B<--coding>

switch to indicate whether or not to score crRNAs for position in coding transcripts.

=item B<--file_base >

A prefix for all output files. This is added to output filenames with a '_' as separator.

=item B<--requestor >

All targets need a requestor. If the requestor is the same for all the targets
supplied to the script it can be supplied here instead of with each target.
If this option is not set, it will be set to 'NULL' to allow for checking that requestors have been 
supplied with each target.

=item B<--no_crRNA>

Option to supress finding and scoring of crRNAs for the targets.
Simply gets the information on the targets and outputs the target info.
Produces target info in a form that is simple to add to the SQL database.

=item B<--debug>

Print debugging information.

=item B<--verbose>

Switch to verbose output mode.

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
