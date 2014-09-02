#!/usr/bin/env perl
# design_pcr_primers_for_illumina_screening.pl

use warnings; use strict;

use Getopt::Long;
use autodie;
use Pod::Usage;
use Readonly;
use Bio::EnsEMBL::Registry;
use List::MoreUtils qw{ any all };

use Crispr;
use Crispr::PrimerDesign;
use Crispr::crRNA;
use Crispr::CrisprPair;

use DateTime;
#get current date
my $date_obj = DateTime->now();
my $todays_date = $date_obj->ymd;

# Default options
my %options = (
    debug => 0,
    restriction_enzymes => 1,
);

# Get and check command line options
get_and_check_options();

if( $options{debug} ){
    use Data::Dumper;
}

# check registry file
if( $options{registry_file} ){
    Bio::EnsEMBL::Registry->load_all( $options{registry_file} );
}
else{
    Bio::EnsEMBL::Registry->load_registry_from_db(
      -host    => 'ensembldb.ensembl.org',
      -user    => 'anonymous',
    );
}

my $primer_design_settings =
        Crispr::PrimerDesign->new(
            config_file => $options{primer3file},
        );

my ( $primer_file, $primer_fh, );
if( $options{file_prefix} ){
    $primer_file = $options{file_prefix} . '_primers.tsv';
}
else{
    $primer_file = $todays_date . '_primers.tsv'; 
}

open $primer_fh, '>', $primer_file;
print {$primer_fh } join("\t", $primer_design_settings->primers_header, ), "\n";

# remove previously existing primer3 output files
my @files = qw{ int_6_primer3.out int_2_primer3.out int_6_primer3.out RM_int.fa RM_ext.fa };
foreach( @files ){
    if( -e $_ ){
        unlink( $_ );
    }
}

# make new Crispr object
my $crispr_design = Crispr->new();

my $targets;
my @ids;

# set up constants
Readonly my $SLICE_EXTENDER => 500;
Readonly my $DISTANCE_TO_TARGET => 125;

my $adaptors_for;
while(<>){
    chomp;
    # accept either crRNA or crispr_pair name.
    my ( $name, $species ) = split /\t/, $_;
    
    # species must be supplied
    if( !$species ){
        if( $options{species} ){
            $species = $options{species};
        }
        else{
            die "Either set the species globally with --species " .
                "or provide a species for each entry!\n";
        }
    }

    # check whether crRNA or pair name
    # need to set up variables to use later # id, start, end, product_addition
    my ( $id, $chr, $start, $end, $product_addition );
    if( $name =~ m/\AcrRNA:[[:alnum:]_]+:   # crRNA:CHR:
                    [0-9]+\-[0-9]+:         # RANGE:
                    [1-]+                   # STRAND
                    _crRNA:[[:alnum:]_]+:[0-9]+\-[0-9]+:[1-]+ #SAME AGAIN JOINED BY UNDERSCORE
                    \z/xms ){ # matches a crispr pair name
        my ( $name1, $name2 ) = split /_/, $name;
        # make crRNA for each name and then Crispr pair
        my $crRNA_1 = $crispr_design->create_crRNA_from_crRNA_name( $name1 );
        my $crRNA_2 = $crispr_design->create_crRNA_from_crRNA_name( $name2 );
        my $crispr_pair = Crispr::CrisprPair->new(
            crRNA_1 => $crRNA_1,
            crRNA_2 => $crRNA_2,
        );
        
        # start and end are cut-sites of respective crRNAs
        $chr = $crRNA_1->chr;
        $start = $crRNA_1->cut_site;
        $end = $crRNA_2->cut_site;
        
        # full crispr pair name is too long for primer3.
        # make short version as $id
        $id = join(':',
                    'crispr_pair',
                    $crRNA_1->chr,
                    join('-',
                        $start,
                        $end,
                    ),
                );
        $targets->{ $id }->{crispr_pair} = $crispr_pair;
        # calculate amount to increase product size by if target is bigger than 100 bp
        
        $product_addition = $crispr_pair->deletion_size > 100    ?
                $crispr_pair->deletion_size
            :   0;
    }
    elsif( $name =~ m/\AcrRNA:[[:alnum:]_]+:    # crRNA:CHR:
                    [0-9]+\-[0-9]+              # RANGE
                    :*[1-]*                     # :STRAND optional
                    \z/xms ){ # matches a single crRNA name
        my $crRNA = $crispr_design->create_crRNA_from_crRNA_name( $name );
        # start and end are the cut site
        $chr = $crRNA->chr;
        $start = $crRNA->cut_site;
        $end = $crRNA->cut_site;
        $id = $crRNA->name;
        $targets->{ $id }->{crRNA} = $crRNA;
    }
    else{
        # doesn't look like a valid crRNA name
        die "Could not parse name, $name.\n";
    }
    
    #get adaptors
    my ( $slice_adaptor, $vfa );
    if( !exists $adaptors_for->{$species} ){
        $slice_adaptor = Bio::EnsEMBL::Registry->get_adaptor( $species, 'core', 'slice' );
        $adaptors_for->{$species}->{'sa'} = $slice_adaptor;
        $vfa = Bio::EnsEMBL::Registry->get_adaptor( $species, 'variation', 'variationfeature');
        $adaptors_for->{$species}->{'vfa'} = $vfa;
    }
    else{
        $slice_adaptor = $adaptors_for->{$species}->{'sa'};
    }
    
    # get slice for deletion
    my $slice = $slice_adaptor->fetch_by_region( 'toplevel', $chr, $start, $end, 1, );
    if( !$slice ){
        die "Couldn't get slice for position, $chr:$start-$end and species, $species!\n";
    }
    my $design_slice;
    # extend slice
    $design_slice = $slice->expand($SLICE_EXTENDER, $SLICE_EXTENDER);
    
    # Check for truncated slices because don't yet handle them properly.
    check_slice( $design_slice, $slice->length, $SLICE_EXTENDER, ) or die 'Slice for ', $slice->name(), " is truncated.\n";
    
    # Trim to avoid Ns
    my $initial_start = $design_slice->start;
    my $initial_end = $design_slice->end;
    while ($design_slice->seq =~ m/N+/g) {
        my $slice_start = $design_slice->start;
        my $slice_end = $design_slice->end;
        my $ns   = length($&);
        my $spos = length($`);
        my $epos = $spos + $ns;
        my $g_spos = $slice_start + $spos - 1;
        my $g_epos = $g_spos + $ns;
        my ($shift_end_left, $shift_start_left, $shift_start_right, $shift_end_right);
        if ($g_spos > $end && (length($') < 30 || $ns > 2)) {
            $shift_end_left = -(length($') + $ns);
            $shift_start_left  = length($') + $ns if $slice_start == $initial_start;
            $design_slice = $design_slice->expand($shift_start_left, $shift_end_left, 1);
        } elsif ($g_spos < $start && ($spos < 30 || $ns > 2)) {
            $shift_start_right = -$epos;
            $shift_end_right = $epos if $slice_end == $initial_end;
            $design_slice = $design_slice->expand($shift_start_right, $shift_end_right, 1);
        }
        warn "Not enough sequence\n" if $design_slice->length < 200;
    }
    
    my $target_start = $start - ( $design_slice->start - 1 );
    my $target_end = $end - ( $design_slice->start - 1 );
    
    # add id to list for printing out in correct order
    push @ids, $id;
    
    $targets->{ $id }->{name} = $name;
    $targets->{ $id }->{chr} = $chr;
    $targets->{ $id }->{start} = $start;
    $targets->{ $id }->{end} = $end;
    $targets->{ $id }->{strand} = 1;
    $targets->{ $id }->{species} = $species;
    $targets->{ $id }->{design_slice} = $design_slice;
    $targets->{ $id }->{target_start} = $target_start;
    $targets->{ $id }->{target_end} = $target_end;
    $targets->{ $id }->{ext_start} = $design_slice->start;
    $targets->{ $id }->{ext_end} = $design_slice->end;
    $targets->{ $id }->{ext_amp} = [
        $id,
        $design_slice->seq,
        undef, # left primer seq
        undef, # right primer seq
        [ [ $target_start, $target_end - ( $target_start - 1 ) ] ], # target
        [ [ $target_start - 100, $target_end + 100 - ( $target_start - 100 ) ] ], # excluded
        undef, # included
        $product_addition, # addition to product size
    ];
}

if( $options{debug} == 2 ){
    print Dumper( $targets );
}

# design PCR primers
# parameters: product size 250-300
my @pcr_size_ranges = (
    {
        ext => '300-600',
        int => '250-300',
    },
    #{
    #    ext => '500-1000',
    #    int => '50-450',
    #},
);
my $round = 0;

foreach my $size_ranges ( @pcr_size_ranges ){
    $targets = primer_design( $targets, $primer_design_settings, $size_ranges );
    if( all { defined $targets->{$_}->{int_primers} } keys %$targets ){
        last;
    }
}

if( ( any { !defined $targets->{$_}->{int_primers} } keys %$targets ) && keys %{$options{primer3_settings}} ){
    # change primer3 settings
    foreach my $prefix ( '2', '6' ){
        foreach my $key ( keys %{$options{primer3_settings}} ){
            $primer_design_settings->primer3adaptor->cfg->{ join('_', $prefix, $key ) } = $options{primer3_settings}->{$key};
        }
    }
    # make a targets hash that is the undesigned subset of $targets
    my @left_over_target_ids = grep { !defined $targets->{$_}->{int_primers} } keys $targets;
    my $left_over_targets;
    %{$left_over_targets} = map { $_ => $targets->{$_} } @left_over_target_ids;
    
    foreach my $size_range ( @pcr_size_ranges ){
        $left_over_targets = primer_design( $left_over_targets, $primer_design_settings, $size_range );
        if( all { defined $targets->{$_}->{int_primers} } keys %$targets ){
            last;
        }
    }
}

# output primers on their own and with partial Illumina adaptors
my @targets_to_print;
Readonly my $LEFT_PARTIAL_ADAPTOR =>
    exists $options{left_adaptor} && defined $options{left_adaptor}
        ? $options{left_adaptor} : 'ACACTCTTTCCCTACACGACGCTCTTCCGATCT';
Readonly my $RIGHT_PARTIAL_ADAPTOR =>
    exists $options{right_adaptor} && defined $options{right_adaptor}
        ? $options{right_adaptor} : 'TCGGCATTCCTGCTGAACCGCTCTTCCGATCT';

foreach my $id ( @ids ){
    my $target_info = $targets->{$id};
    push @targets_to_print, $target_info;
    
    my @primer_info;
    if( defined $target_info->{ext_primers} ){
        push @primer_info, $target_info->{ext_primers}->pair_name,
            $target_info->{ext_primers}->left_primer->primer_name,
            $target_info->{ext_primers}->left_primer->seq,
            $target_info->{ext_primers}->right_primer->primer_name,
            $target_info->{ext_primers}->right_primer->seq,
            ;
        if( defined $target_info->{int_primers} ){
            push @primer_info, $target_info->{int_primers}->pair_name,
                $target_info->{int_primers}->left_primer->primer_name,
                $target_info->{int_primers}->left_primer->seq,
                $target_info->{int_primers}->right_primer->primer_name,
                $target_info->{int_primers}->right_primer->seq,
                join(':', $target_info->{int_primers}->pair_name, 'partial_adaptor'),
                join(':', $target_info->{int_primers}->left_primer->primer_name, 'partial_adaptor'),
                $LEFT_PARTIAL_ADAPTOR . $target_info->{int_primers}->left_primer->seq,
                join(':', $target_info->{int_primers}->right_primer->primer_name, 'partial_adaptor'),
                $RIGHT_PARTIAL_ADAPTOR . $target_info->{int_primers}->right_primer->seq,
                ;
        }
        else{
            push @primer_info, ( 'NO INT PRIMERS', '' x 9, );
        }
    }
    else{
        @primer_info = ( 'NO EXT PRIMERS', '' x 14, );
    }
    
    if( exists $target_info->{crispr_pair} ){
        my $crispr_pair = $target_info->{crispr_pair};
        
        my $sizes;
        if( defined $target_info->{int_primers} ){
            $sizes = join('/', $target_info->{int_primers}->product_size,
                        $target_info->{int_primers}->product_size -
                            $crispr_pair->deletion_size );
        }
        foreach my $crRNA ( @{ $crispr_pair->crRNAs } ){
            my @enzyme_information;
            if( $options{restriction_enzymes} ){
                @enzyme_information = get_enzyme_information( $crRNA, );
            }
            print join("\t", $crispr_pair->pair_name, $crRNA->name,
                        @primer_info, join(q{,}, @enzyme_information, ),
                        $sizes || '', ), "\n";
        }
    }
    elsif( exists $target_info->{crRNA} ){
        my @info;
        my $crRNA = $target_info->{crRNA};
        my @enzyme_information;
        my $product_size;
        if( $options{restriction_enzymes} ){
            @enzyme_information = get_enzyme_information( $crRNA, );
        }
        if( defined $target_info->{int_primers} ){
            $product_size = $target_info->{int_primers}->product_size;
        }
        push @info, 'NULL', $crRNA->name;
        print join("\t", @info, @primer_info, join(q{,}, @enzyme_information, ), $product_size || 'NULL', ), "\n";
    }
    else{
        die "This shouldn't happen. There is a crispr_pair or a crRNA!\n";
    }
}

# output primer info to file
$primer_design_settings->print_primers_to_file( \@targets_to_print, 'int', $primer_fh, );


###   SUBROUTINES   ###
# check_slice
# 
#   Usage       : check_slice( $design_slice, $slice->length, $SLICE_EXTENDER, )
#   Purpose     : Check for truncated slices
#   Returns     : 1 if slice is ok, 0 otherwise.
#   Parameters  : Bio::EnsEMBL::Slice object
#                 The length of the original slice
#                 The amount by which the slice has been expanded
#   Throws      : 
#   Comments    : Need to change the code that uses this to deal properly with a truncated slice
# 


sub check_slice {
    my ( $slice, $slice_length, $SLICE_EXTENDER ) = @_;
    my $ok = 1;
    my $seq = $slice->seq();
    $ok = 0 if length($seq) != $slice_length + 2*$SLICE_EXTENDER;
    
    return $ok;
}

# primer_design
# 
#   Usage       : primer_design( $targets, $primer_design_settings, $size_range, )
#   Purpose     : Goes through several rounds of primer design to design primers
#                 for each target in the $targets HASH
#   Returns     : HashRef of targets
#   Parameters  : HashRef of targets and parameters
#                 Crispr::PrimerDesign object
#                 The desired pcr product size range
#   Throws      : 
#   Comments    : None
# 


sub primer_design {
    my ( $targets, $primer_design_settings, $size_ranges, ) = @_;
    my $ext_range = $size_ranges->{ext};
    my $int_range = $size_ranges->{int};
    
    # DESIGN PRIMERS
    ##  EXTERNAL PRIMERS - ROUND 1 ##
    $round++;
    $targets = $primer_design_settings->design_primers($targets, 'ext', $ext_range, 6, $round, 1, 1, $adaptors_for, );
    
    ##  EXTERNAL PRIMERS - ROUND 2 ##
    foreach my $id (sort keys %$targets) {
        if (!defined $targets->{$id}->{ext_primers}) {
            my $target_start = $targets->{ $id }->{target_start};
            my $target_end = $targets->{ $id }->{target_end};
            $targets->{$id}->{ext_amp}[5] = 
            [ [$target_start - 100, $target_end + 100 - ( $target_start - 100 ) ] ];
        }
    }
    $round++;
    $targets = $primer_design_settings->design_primers($targets, 'ext', $ext_range, 6, $round, 0, 1, $adaptors_for, );
    
    ##  EXTERNAL PRIMERS - ROUND 3 ##
    foreach my $id (sort keys %$targets) {
        if (!defined $targets->{$id}->{ext_primers}) {
            my $target_start = $targets->{ $id }->{target_start};
            my $target_end = $targets->{ $id }->{target_end};
            $targets->{$id}->{ext_amp}[5] = 
            [ [$target_start - 100, $target_end + 100 - ( $target_start - 100 ) ] ];
        }
    }
    $round++;
    $targets = $primer_design_settings->design_primers($targets, 'ext', $ext_range, 6, $round, 0, 0, $adaptors_for, );
    
    foreach my $id ( sort keys %{$targets} ){
        if( defined $targets->{$id}->{'ext_primers'} ){
            # get new design slice to match external primers
            my $species = $targets->{$id}->{'species'};
            my $slice_adaptor = $adaptors_for->{$species}->{'sa'};
            my $slice = $slice_adaptor->fetch_by_region( 'toplevel',
            $targets->{ $id }->{chr}, $targets->{ $id }->{ext_start},
            $targets->{ $id }->{ext_end}, $targets->{ $id }->{strand} );            
            $targets->{ $id }->{design_slice} = $slice;
            
            # set up info for internal primers
            $targets->{$id}->{int_start}    = $targets->{$id}->{ext_start};
            $targets->{$id}->{int_end}      = $targets->{$id}->{ext_end};
            my ( $target_start, $target_end );
            $target_start = $targets->{$id}->{start} - $targets->{$id}->{int_start};
            $target_end = $targets->{$id}->{end} - $targets->{$id}->{int_start};
            $targets->{ $id }->{target_start} = $target_start;
            $targets->{ $id }->{target_end} = $target_end;
            $targets->{$id}->{int_amp} = [
                $id,
                $targets->{$id}->{design_slice}->seq,
                undef,
                undef,
                [ [ $target_start, $target_end - ( $target_start - 1 ) ] ], # target
                [  ], # excluded
                undef,
                $targets->{ $id }->{ext_amp}->[7],
            ];
        }
    }
    
    my @target_offsets = ( 25, 10 );
    
    foreach my $side ( 'left', 'right' ){
        foreach my $target_offset ( @target_offsets ){
            ##  PRIMERS - ROUND 1 ##
            $round++;
            # reset excluded regions to remove effects of repeat/variation masking
            $targets = reset_excluded_regions( $targets, $target_offset, $side, );
            if( $options{debug} == 2 ){
                print Dumper( $targets );
            }
            $targets = $primer_design_settings->design_primers($targets, 'int', $int_range, 6, $round, 1, 1, $adaptors_for, !$options{restriction_enzymes}, );
            
            ##  INTERNAL PRIMERS - ROUND 2 ##
            if( all { defined $targets->{$_}->{int_primers} } keys %$targets ){
                return $targets;
            }
            $round++;
            $targets = reset_excluded_regions( $targets, $target_offset, $side, );
            $targets = $primer_design_settings->design_primers($targets, 'int', $int_range, 2, $round, 1, 1, $adaptors_for, !$options{restriction_enzymes}, );    
            
            ##  INTERNAL PRIMERS - ROUND 3 ##
            if( all { defined $targets->{$_}->{int_primers} } keys %$targets ){
                return $targets;
            }
            $round++;
            $targets = reset_excluded_regions( $targets, $target_offset, $side, );
            $targets = $primer_design_settings->design_primers($targets, 'int', $int_range, 6, $round, 0, 1, $adaptors_for, !$options{restriction_enzymes}, );
            
            ##  INTERNAL PRIMERS - ROUND 4 ##
            if( all { defined $targets->{$_}->{int_primers} } keys %$targets ){
                return $targets;
            }
            $round++;
            $targets = reset_excluded_regions( $targets, $target_offset, $side, );
            $targets = $primer_design_settings->design_primers($targets, 'int', $int_range, 2, $round, 0, 1, $adaptors_for, !$options{restriction_enzymes}, );
            
            ##  INTERNAL PRIMERS - ROUND 5 ##
            if( all { defined $targets->{$_}->{int_primers} } keys %$targets ){
                return $targets;
            }
            $round++;
            $targets = reset_excluded_regions( $targets, $target_offset, $side, );
            $targets = $primer_design_settings->design_primers($targets, 'int', $int_range, 6, $round, 0, 0, $adaptors_for, !$options{restriction_enzymes}, );
            
            ##  INTERNAL PRIMERS - ROUND 6 ##
            if( all { defined $targets->{$_}->{int_primers} } keys %$targets ){
                return $targets;
            }
            $round++;
            $targets = $primer_design_settings->design_primers($targets, 'int', $int_range, 2, $round, 0, 0, $adaptors_for, !$options{restriction_enzymes}, );
        }
    }
    return $targets;
}

# reset_excluded_regions
# 
#   Usage       : reset_excluded_regions( $crRNA, )
#   Purpose     : resets the element of the amp array that corresponds to excluded positions
#                 to remove variation/repeat masking
#   Returns     : targets HashRef
#   Parameters  : targets HashRef
#                 target_offset   Int
#   Throws      : 
#   Comments    : Also adds an excluded region to one side to make sure that at
#                 least one of the reads is closer than 125 bp to the crispr cut-site.
#                 This is biased towards the left side (read1).


sub reset_excluded_regions {
    my ( $targets, $target_offset, $side_to_constrain) = @_;
    
    foreach my $id (sort keys %$targets) {
        if ( !defined $targets->{$id}->{int_primers}) {
            my $target_start = $targets->{ $id }->{target_start};
            my $target_end = $targets->{ $id }->{target_end};
            my $ext_p    = $targets->{$id}->{ext_primers};
            $targets->{$id}->{int_amp}[5] =
                [
                    [ 1, $ext_p->left_primer->length - 10 ],
                    [ $ext_p->product_size - 10, 10 ],
                    [ $target_start - $target_offset, ($target_end + $target_offset) - ($target_start - $target_offset) + 1 ],
                ];
            
            if( $target_start > $DISTANCE_TO_TARGET && $side_to_constrain eq 'left' ){
                push @{$targets->{$id}->{int_amp}[5]},
                    [ 1, $target_start - $DISTANCE_TO_TARGET ];
            }
            if( $targets->{$id}->{int_end} - $targets->{$id}->{end} > $DISTANCE_TO_TARGET && $side_to_constrain eq 'right' ){
                push @{$targets->{$id}->{int_amp}[5]},
                    [ $target_end + $DISTANCE_TO_TARGET, $targets->{$id}->{int_end} - $targets->{$id}->{end} - $DISTANCE_TO_TARGET ];
            }
        }
    }
    
    return $targets;
}

# get_enzyme_information
# 
#   Usage       : get_enzyme_information( $crRNA, )
#   Purpose     : Gets the unique restriction sites within the supplied crRNA
#                 and returns the enzymes sorted by proximity to cut-site
#                 and then restriction site length length.
#                 Takes the top 5 enzymes including ties.
#   Returns     : Array of colon-separated list of enzyme name, site and proximity to cut-site
#   Parameters  : Crispr::crRNA object
#   Throws      : 
#   Comments    : None
# 


sub get_enzyme_information {
    my ( $crRNA, ) = @_;
    warn $crRNA->name, "\n" if $options{debug};
    my @enzymes;
    my $enzyme_info;
    my @enzyme_information;
    if( defined $crRNA->unique_restriction_sites ){
        $enzyme_info = $crRNA->unique_restriction_sites;
        if( $enzyme_info->uniq_in_both->each_enzyme() ){
            # sort by Schwartzian Transform
            # first create an array of arrays including value and sortkey
            # sort by sortkey
            # later retrieve original values with map
            my @sorted_enzymes_sw = sort { $a->[1] <=> $b->[1] ||
                    length($a->[0]->string) <=> length($b->[0]->string)}  # sort
                map { [$_, $enzyme_info->proximity_to_cut_site( $_, $crRNA, )] }
                    $enzyme_info->uniq_in_both->each_enzyme(); # transform: value, sortkey
            
            # take top five including ties
            my $proximity = 0;
            my $i = 0;
            if( scalar @sorted_enzymes_sw < 6 ){
                @enzymes = map { $_->[0] } @sorted_enzymes_sw; # map to restore values (enzymes)
            }
            else{
                for( ; $i < scalar @sorted_enzymes_sw; $i++ ){
                    if( $i > 4 && $sorted_enzymes_sw[$i]->[1] > $proximity ){
                        last;
                    }
                    elsif( $i <= 4 ){
                        $proximity = $sorted_enzymes_sw[$i]->[1];
                    }
                }
                $i--;
                
                @enzymes = map { $_->[0] } @sorted_enzymes_sw[ 0..$i ]; # map to restore values (enzymes)
            }
        }
        if( $options{debug} ){
            unshift @enzyme_information, $enzyme_info->analysis->seq->seq;
        }
    }
    if( @enzymes ){
        push @enzyme_information, map { join(':',
                                            $_->name,
                                            $_->site,
                                            $enzyme_info->proximity_to_cut_site( $_, $crRNA, ) )
                                        } @enzymes;
    }
    else{
        push @enzyme_information, 'NULL'; 
    }
    return @enzyme_information;
}

# get_and_check_options
# 
#   Usage       : get_and_check_options()
#   Purpose     : Gets options passed to program and does some checking of those options
#   Returns     : 1 if subroutine exectutes completely
#   Parameters  : 
#   Throws      : 
#   Comments    : Need to add some code for checking existance of registry file
#                 and primer3 file.
# 


sub get_and_check_options {
    
    GetOptions(
        \%options,
        'registry_file=s',
        'primer3file=s',
        'species=s',
        'left_adaptor=s',
        'right_adaptor=s',
        'file_prefix=s',
        'restriction_enzymes!',
        'primer3_settings=f%',
        'debug+',
        'help',
        'man',
    ) or pod2usage(2);
    
    # Documentation
    if( $options{help} ) {
        pod2usage(1);
    }
    elsif( $options{man} ) {
        pod2usage( -verbose => 2 );
    }
    
    if( !$options{primer3file} ){
        my $msg = "Primer3 config file is required!\n";
        pod2usage( $msg );
    }
    elsif( !-e $options{primer3file} || !-r $options{primer3file} ||
            !-f $options{primer3file} ){
        my $msg = join(q{ }, 'Primer3 config file,', $options{primer3file},
            'either does not exist or is not readable!', ) . "\n";
        pod2usage( $msg );
    }
    
    if( $options{registry_file} && !-e $options{registry_file} ){
        warn 'WARNING: Registry file, ', $options{registry_file},
            " does not exist.\nWill try connecting to Ensembl anonymously...\n";
    }
    
    print "Settings:\n", map { join(' - ', $_, defined $options{$_} ? $options{$_} : 'off'),"\n" } sort keys %options if $options{verbose};
    
    return 1;
}


__END__

=pod

=head1 NAME

design_pcr_primers_for_illumina_screening.pl

=head1 DESCRIPTION

Design PCR primers for screening by Illumina Sequencing.

=head1 SYNOPSIS

    design_pcr_primers_for_illumina_screening.pl [options] crRNA names | crispr_pair names
        --registry                  a registry file for connecting to the Ensembl database
        --primer3file               configuration file for primer3
        --species                   A species to use for all input
        --left_adaptor              option to change the default left primer adaptor
        --right_adaptor             option to change the default right primer adaptor
        --file_prefix               a common prefix for primer output files
        --restriction_enzymes       output unique restriction enzyme info for each crRNA
        --norestriction_enzymes     turn off restriction enzyme output
        --help                      prints help message and exits
        --man                       prints manual page and exits
        --debug                     prints debugging information

=head1 DESCRIPTION

design_pcr_primers_for_illumina_screening.pl takes names of crRNAs or crRNA pairs
and designs pcr primers to produce Illumina sequencing libraries. The pcr pairs
are nested with the internal pairs including partial adaptor sequence to construct
a sequencing library.
Input should be tab-separated of form:
crRNA(_pair)_name   Species

Species can be provided globally via the --species option.

Detailed information about the primers is printed to a _primers.tsv file and
summary information is output to STDOUT.

=head1 REQUIRED ARGUMENTS

=over

=item B<input_file>

Tab-separated file of crRNA/crRNA_pair names and species.
This can also be supplied on STDIN.

=back

=head1 OPTIONS

=over

=item B<--registry>

A registry file for connecting to the Ensembl database.
If no file is supplied the script connects anonymously to the current version of the database.

=item B<--primer3file>

configuration file for Primer3

=item B<--species>

A species to use for all input. A species specified in the input file overrides
this option.

=item B<--left_adaptor>

option to change the default left primer adaptor.
This is added to the 5 prime end of the left internal primer.

Default: ACACTCTTTCCCTACACGACGCTCTTCCGATCT (Illumina)

=item B<--right_adaptor>

option to change the default right primer adaptor.
This is added to the 5 prime end of the right internal primer.

Default: TCGGCATTCCTGCTGAACCGCTCTTCCGATCT (Illumina)

=item B<--file_prefix>

a common file prefix for all output files.

=item B<--restriction_enzymes>

Turns on outputting of unique restriction enzyme info for each crRNA.
default: ON

=item B<--norestriction_enzymes>

Turns off outputting of unique restriction enzyme info for each crRNA.

=item B<--help>

prints help message and exits

=item B<--man>

prints manual page and exits

=item B<--debug>

prints debugging information

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
