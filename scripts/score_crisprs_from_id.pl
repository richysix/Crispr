#!/usr/bin/env perl

# PODNAME: score_crisprs_from_id.pl
# ABSTRACT: Score crisprs/crispr pair for off-target/coding from ids.

use warnings; use strict;
use Bio::EnsEMBL::Registry;
use Pod::Usage;
use Crispr;
use Crispr::crRNA;
use Crispr::Target;
use Crispr::CrisprPair;
use Getopt::Long;
use List::MoreUtils qw( any none uniq );
use Readonly;
use Number::Format;
my $num = new Number::Format( DECIMAL_DIGITS => 3, );

# get current date
use DateTime;
my $date_obj = DateTime->now();
my $todays_date = $date_obj->ymd;

# Get and check command line options
my %options;
get_and_check_options();

if( $options{debug} ){
    use Data::Dumper;
}

# make design object
my $crispr_design = Crispr->new(
    species => $options{species},
    target_genome => $options{target_genome},
    annotation_file => $options{annotation_file},
    target_seq => $options{target_sequence},
    five_prime_Gs => $options{num_five_prime_Gs},
    scored => 0,
    debug => $options{debug},
);

# make basename for output files
my $basename = $todays_date;
$basename =~ s/\A/$options{file_base}_/xms if( $options{file_base} );

# open output files
my $output_filename = $basename . '.scored.txt';
open my $out_fh_1, '>', $output_filename or die "Couldn't open file, $output_filename:$!\n";

my %crisprs;
my @crisprs;
my @crispr_pairs;
my %targets;
while(<>){
    chomp;
    my ( $name, $requestor, $target_name, $gene_id, $gene_name, ) = split /\t/, $_;
    
    my $target;
    if( exists $targets{$target_name} ){
        $target = $targets{$target_name};
    }
    else{
        $target = Crispr::Target->new(
            target_name => $target_name,
            requestor => $requestor,
            gene_id  => $gene_id,
            gene_name => $gene_name,
            species => $options{species},
        ),
        $targets{$target_name} = $target;
    }
    
    if( $options{singles} ){
        if( $name !~ m/\AcrRNA:[[:alnum:]_]+:    # crRNA:CHR:
                            [0-9]+\-[0-9]+              # RANGE
                            :*[1-]*                     # :STRAND optional
                            \z/xms ){ # matches a single crRNA name
            die "Supplied id does not match a crRNA name: $name\n";
        }
        my $crRNA;
        if( exists $crisprs{$name} ){
            $crRNA = $crisprs{$name};
        }
        else{
            $crRNA = $crispr_design->create_crRNA_from_crRNA_name( $name, $options{species}, );
            $crRNA->five_prime_Gs( $options{num_five_prime_Gs} ) if exists $options{num_five_prime_Gs};
    
            $crRNA->target( $target );
            $crisprs{$name} = $crRNA;
        }
        push @crisprs, $crRNA;
    } else{
        if( $name !~ m/\AcrRNA:[[:alnum:]_]+:   # crRNA:CHR:
                            [0-9]+\-[0-9]+:         # RANGE:
                            [1-]+                   # STRAND
                            \.crRNA:[[:alnum:]_]+:[0-9]+\-[0-9]+:[1-]+ #SAME AGAIN JOINED BY DOT
                            \z/xms ){ # matches a crispr pair name
            die "Supplied id does not match a crispr pair name: $name\n";
        }
        else{
            my @names = split /\./, $name;
            # make crRNA for each name and then Crispr pair
            my @crRNAs;
            for( my $i = 0; $i < 2; $i++ ){
                my $crRNA;
                if( exists $crisprs{ $names[$i] } ){
                    $crRNA = $crisprs{ $names[$i] };
                }
                else{
                    $crRNA = $crispr_design->create_crRNA_from_crRNA_name( $names[$i], $options{species}, );
                    $crisprs{ $names[$i] } = $crRNA;
                }
                $crRNA->target( $target );
                $crRNA->five_prime_Gs( $options{num_five_prime_Gs} ) if exists $options{num_five_prime_Gs};
                $crRNAs[$i] = $crRNA;
            }
            
            my $crispr_pair = Crispr::CrisprPair->new(
                crRNA_1 => $crRNAs[0],
                crRNA_2 => $crRNAs[1],
            );
            push @crisprs, $crRNAs[0], $crRNAs[1];
            push @crispr_pairs, $crispr_pair;
        }
    }
}

warn Dumper( @crisprs, @crispr_pairs ) if $options{debug};
$crispr_design->add_crisprs( \@crisprs );

# score off targets using bwa
$crispr_design->find_off_targets( $crispr_design->all_crisprs, $basename, );

Readonly my $WINDOW_SIZE => defined $options{max_off_target_separation}    ?   $options{max_off_target_separation}
    :                                                                       10000;

# score off-targets in pairs if need be
if( $options{pairs} ){
    foreach my $cr_pair ( @crispr_pairs ){
        my %relevant_crRNAs_lookup = map { $_->name => 1 } @{$cr_pair->crRNAs};
        # hash of paired targets already seen
        my %pair_off_targets_seen;
        foreach my $crRNA ( @{$cr_pair->crRNAs} ){
            #my $id = $crRNA->name . "_" . $crRNA->target->target_name;
            #my $crRNA = $crispr_design->all_crisprs->{$id};
            warn Dumper( $crRNA ) if $options{debug} > 1;
            if( $crRNA->off_target_hits->all_off_targets ){
                foreach my $off_target_obj ( $crRNA->off_target_hits->all_off_targets ){
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
                        
                        next if exists $pair_off_targets_seen{ join("_", $off_target_obj->position, $off_target_info->position ) };
                        $pair_off_targets_seen{ join("_", $off_target_obj->position, $off_target_info->position ) } = 1;
                        $pair_off_targets_seen{ join("_", $off_target_info->position, $off_target_obj->position ) } = 1;
                        
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
                        $cr_pair->increment_paired_off_targets( $increment );
                    }
                }
            }
        }
    }
}

sub cut_site {
    my ( $start, $end, $strand ) = @_;
    return $strand == 1 ? $end - 6 : $start + 5;
}

if( $options{singles} ){
    print $out_fh_1 "#", join("\t", $crispr_design->target_summary_header(), $crispr_design->crRNA_info_header(), ), "\n";
    
    foreach my $crRNA ( @crisprs ){
        print $out_fh_1 join("\t", $crRNA->target_summary_plus_crRNA_info,
                             join(';', $crRNA->notes, ) ), "\n";
    }
}
else{
    my @header_columns = ( 
        '#pair_name', qw{ number_paired_off_target_hits combined_score deletion_size
        target_1_name target_1_species target_1_requestor
        crRNA_1_name crRNA_1_chr crRNA_1_start crRNA_1_end crRNA_1_strand
        crRNA_1_score crRNA_1_sequence crRNA_1_oligo1 crRNA_1_oligo2 crRNA_1_off_target_score
        crRNA_1_off_target_counts crRNA_1_off_target_hits crRNA_1_coding_score
        crRNA_1_coding_scores_by_transcript crRNA_1_five_prime_Gs crRNA_1_plasmid_backbone crRNA_1_GC_content
        target_2_name target_2_species target_2_requestor
        crRNA_2_name crRNA_2_chr crRNA_2_start crRNA_2_end crRNA_2_strand
        crRNA_2_score crRNA_2_sequence crRNA_2_oligo1 crRNA_2_oligo2 crRNA_2_off_target_score
        crRNA_2_off_target_counts crRNA_2_off_target_hits crRNA_2_coding_score
        crRNA_2_coding_scores_by_transcript crRNA_2_five_prime_Gs crRNA_2_plasmid_backbone crRNA_2_GC_content } );
    print $out_fh_1 join("\t", @header_columns, ), "\n";
    
    foreach my $cr_pair ( @crispr_pairs ){
        print $out_fh_1 join("\t", 
            $cr_pair->name, $cr_pair->paired_off_targets || 0,
            $num->format_number($cr_pair->combined_single_off_target_score),
            $cr_pair->deletion_size,
            $cr_pair->crRNA_1->target_name,
            $cr_pair->crRNA_1->target->species,
            $cr_pair->crRNA_1->target->requestor,
            $cr_pair->crRNA_1->info,
            $cr_pair->crRNA_2->target_name,
            $cr_pair->crRNA_2->target->species,
            $cr_pair->crRNA_2->target->requestor,
            $cr_pair->crRNA_2->info, ), "\n";
    }    
}

sub get_and_check_options {
    GetOptions(
        \%options,
        'singles',
        'pairs',
        'species=s',
        'target_genome=s',
        'annotation_file=s',
        'target_sequence=s',
        'num_five_prime_Gs=i',
        'max_off_target_separation=i',
        'file_base=s',
        'debug+',
        'verbose',
        'help',
        'man',
    ) or pod2usage(2);
    
    # Documentation
    if( $options{help} ) {
        pod2usage( -verbose => 0, -exitval => 1 );
    }
    elsif( $options{man} ) {
        pod2usage( -verbose => 2 );
    }
    
    if( exists $options{singles} && exists $options{pairs} ){
        pod2usage( "Can't specify both --singles and --pairs!\n" );
    }
    if( !exists $options{singles} && !exists $options{pairs} ){
        warn "Neither option of --singles or --pairs specified. Assuming --singles...\n";
        $options{singles} = 1;
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
    
    return 1;
}

__END__

=pod

=head1 NAME

score_crisprs_from_id.pl

=head1 DESCRIPTION

Scores crispr target sites/crispr pairs for off-target sites.

=head1 SYNOPSIS

    score_crisprs_from_id.pl [options] filename(s) | target info on STDIN
        --singles                       option specifying that inputs are single crisprs
        --pairs                         option specifying that inputs are crispr pairs
        --species                       species for the targets
        --target_genome                 a target genome fasta file for scoring off-targets
        --annotation_file               an annotation gff file for scoring off-targets
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

=item Target info: Tab-separated  CRISPR_NAME/CRISPR_PAIR_NAME  TARGET_NAME REQUESTOR

=item CRISPR_NAME is the position of the crispr site in the form crRNA:CHR:START-END:STRAND e.g. crRNA:10:1001-1023:-1

=item CRISPR_PAIR_NAME is the two CRISPR_NAMES joined by an '.' e.g. crRNA:10:1001-1023:-1.crRNA:10:1030-1052:1

=back

=back

=head1 OPTIONS

=over

=item B<--singles>

option specifying that inputs are single crisprs. This is the default.

=item B<--pairs>

option specifying that inputs are crispr pairs. --singles and --pairs cannot be specified together.

=item B<--species >

The relevant species for the supplied targets.

=item B<--target_genome >

The path of the target genome file. This needs to have been indexed by bwa in order to score crispr off-targets.

=item B<--annotation_file >

The path of the annotation file for the appropriate species. Must be in gff format.

=item B<--target_sequence >

The Cas9 target sequence [default: NNNNNNNNNNNNNNNNNNNNNGG ]
This sequence must match the --num_five_prime_Gs option if set.

=item B<--num_five_prime_Gs >

The numbers of Gs required at the 5' end of the target sequence.
e.g. 1 five prime G has a target sequence GNNNNNNNNNNNNNNNNNNNNGG. [default: 0]
Must be compatible with --target_sequence if set.

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
