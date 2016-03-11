## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::PrimerDesign;

## use critic

# ABSTRACT: primer design object - for designing primers using primer3

## Author         : rw4
## Maintainer     : rw4
## Created        : 2013-02-25
## Last commit by : $Author$
## Last modified  : $Date$
## Revision       : $Revision$
## Repository URL : $HeadURL$

use warnings;
use strict;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use Bio::EnsEMBL::Registry;
use Crispr::EnzymeInfo;
use Crispr::Config;
use PCR::Primer3;
use Bio::Restriction::EnzymeCollection;
use Bio::Restriction::Analysis;
use List::MoreUtils qw{ any };
use Carp qw{ cluck confess };

=method new

  Usage       : my $primer_design = Crispr::PrimerDesign->new(
                    config_file => 'config_file.txt',
                    rebase_file => 'withrefm.405',
                );
  Purpose     : Constructor for creating Crispr objects
  Returns     : Crispr object
  Parameters  : config_file         => Str
                cfg                 => Crispr::Config,
                primer3adptor       => PCR::Primer3,
                rebase_file         => Str
                enzyme_collection   => Bio::Restriction::EnzymeCollection,
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method config_file

  Usage       : $crispr_design->config_file;
  Purpose     : Getter/Setter for config_file attribute
  Returns     : Str
  Parameters  : Str
  Throws      : 
  Comments    : 

=cut

has 'config_file' => (
    is => 'rw',
    isa => 'Str',
);

=method cfg

  Usage       : $crispr_design->cfg;
  Purpose     : Getter/Setter for cfg attribute
  Returns     : Str
  Parameters  : Str
  Throws      : 
  Comments    : 

=cut

has 'cfg' => (
    is => 'rw',
    isa => 'Crispr::Config',
    builder => '_build_config',
    lazy => 1,
);

=method primer3adaptor

  Usage       : $crispr_design->primer3adaptor;
  Purpose     : Getter for primer3adaptor attribute
  Returns     : Str
  Parameters  : Str
  Throws      : 
  Comments    : 

=cut

has 'primer3adaptor' => (
    is => 'ro',
    isa => 'PCR::Primer3',
    builder => '_build_adaptor',
    lazy => 1,
);

=method rebase_file

  Usage       : $crispr_design->rebase_file;
  Purpose     : Getter for rebase_file attribute
  Returns     : Str
  Parameters  : Str
  Throws      : 
  Comments    : 

=cut

has 'rebase_file' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

=method enzyme_collection

  Usage       : $crispr_design->enzyme_collection;
  Purpose     : Getter for enzyme_collection attribute
  Returns     : Str
  Parameters  : Str
  Throws      : 
  Comments    : 

=cut

has 'enzyme_collection' => (
    is => 'ro',
    isa => 'Bio::Restriction::EnzymeCollection',
    builder => '_build_enzyme_collection',
    lazy => 1,
);

=method _build_config

  Usage       : $crispr_design->_build_config;
  Purpose     : Internal method to create Crispr::Config object from config file
  Returns     : Crispr::Config
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub _build_config {
    my ( $self, ) = @_;
    my $cfg;
    if( $self->config_file ){
        $cfg = Crispr::Config->new($self->config_file);
    }
    else{
        die "Primer3 config file must be set!: $!\n"; 
    }
    return $cfg;
};

=method _build_adaptor

  Usage       : $crispr_design->_build_adaptor;
  Purpose     : Internal method to make new PCR::Primer3 object from config file
  Returns     : PCR::Primer3
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub _build_adaptor {
    my ( $self ) = @_;
    my $primer3adaptor = PCR::Primer3->new( cfg => $self->cfg );
    return $primer3adaptor;
}

=method _build_enzyme_collection

  Usage       : $crispr_design->_build_enzyme_collection;
  Purpose     : Internal method to create a new Bio::Restriction::EnzymeCollection object from a REBASE file
  Returns     : Bio::Restriction::EnzymeCollection
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub _build_enzyme_collection {
    my ( $self, ) = @_;
    my $collection;
    if( $self->rebase_file && -e $self->rebase_file ){
        my $rebase = Bio::Restriction::IO->new(
            -file   => $self->rebase_file,
            -format => 'withrefm'
        );
        $collection = $rebase->read();
    }
    else{
        $collection = Bio::Restriction::EnzymeCollection->new();
    }
    return $collection;
}

=method design_primers

  Usage       : $targets = design_primers($targets, 'ext', '450-800', 6, 1, 1, 1, $adaptors_for, 1);
  Purpose     : Design PCR primers
  Returns     : Hashref of primers and settings
  Parameters  : Hashref of target info
                Type of primers ( 'ext', 'int', 'hrm' )
                Size range of amplicon
                Number denoting Primer3 settings from Primer config file
                Round of primer design
                Repeatmask flag
                Variationmask flag
                Hashref of Bio::EnsEMBL::DBSQL::SliceAdaptor and
                Bio::EnsEMBL::DBSQL::VariationFeatureAdaptor adaptors for
                particular species (e.g. $hashref->{species}->{sa || vfa})
                Restriction Digest flag
  Throws      : 
  Comments    : None

=cut

sub design_primers {
    my ( $self, $targets, $type, $size_range, $settings, $round,
        $repeat_mask, $variation_mask, $adaptors_for, $no_unique_re) = @_;
    
    # Create FASTA file for RepeatMasker
    my $amps = $self->fasta_for_repeatmask($targets, $type);
    if (scalar(@$amps)){
        if( $repeat_mask ){
            $targets = $self->repeatmask($targets, $type, );
        }
        if( $variation_mask ){
            $targets = $self->variationmask( $targets, $type, $adaptors_for, );
        }
        
        #print Dumper( %{$targets} );
        
        my $primer3_file = $self->primer3adaptor->setAmpInput($amps, undef, undef, $size_range, $settings, $round, '.');
        my $potential_primers  = $self->primer3adaptor->primer3($primer3_file, $type . '_' . $settings . '_primer3.out');
        
        my @primers_to_sort;
        if( @{$potential_primers} && $type eq 'int' ){
            foreach my $primer_pair ( @{$potential_primers} ){
                my $id = $primer_pair->amplicon_name;
                if ($primer_pair->left_primer->seq && $primer_pair->right_primer->seq
                    && !defined $targets->{$id}->{$type . '_primers'}) {
                    my $target_info = $targets->{$id};
                    
                    #use Data::Dumper;
                    #print Dumper( $primer_pair );
                    my $ok;
                    if( $no_unique_re ){
                        $ok = 1;
                    }
                    else{
                        ( $ok, undef ) = $self->check_for_unique_re_in_amplicon_and_crRNAs( $primer_pair, $type, $target_info, $id, $adaptors_for );
                    }
                    push @primers_to_sort, $primer_pair if $ok;
                }
            }
        }
        elsif( @{$potential_primers} ){
            @primers_to_sort = @{$potential_primers};
        }
        
        if( @primers_to_sort ){
            $targets = $self->sort_and_select_primers( \@primers_to_sort, $type, $round, $targets, $adaptors_for, !$no_unique_re );
        }
        
        # if no internal primers match go through again, no longer checking restriction sites
        if( $type eq 'int' && @{$potential_primers} ){
            $targets = $self->sort_and_select_primers( $potential_primers, $type, $round, $targets, $adaptors_for, 0 );
        }
        
    }
    return $targets;
}

=method design_primers_multiple_rounds_nested

  Usage       : $targets = design_primers_multiple_rounds_nested($targets, \@size_ranges, \%adaptors_for, );
  Purpose     : wrapper function to do several rounds of nested primer design
                changing the parameters each time
  Returns     : Hashref of primers and settings
  Parameters  : Hashref of target info
                ArrayRef of HashRefs of amplicon Size ranges
                Hashref of Bio::EnsEMBL::DBSQL::SliceAdaptor and
                Bio::EnsEMBL::DBSQL::VariationFeatureAdaptor adaptors for
                particular species (e.g. $hashref->{species}->{sa || vfa})
  Throws      : If Arguments are not appropriate objects
  Comments    : None

=cut

sub design_primers_multiple_rounds_nested {
    my ( $self, $targets, $size_ranges, $adaptors_for ) = @_;
    if( !$targets ){
        confess "Target information must be supplied.\n";
    }
    elsif( !ref $targets || ref $targets ne 'HASH' ){
        confess "The first argument must be a HashRef not ",
            ref $targets, ".\n";
    }
    
    if( !$size_ranges ){
        confess "Size ranges must be supplied.\n";
    }
    elsif( !ref $size_ranges || ref $size_ranges ne 'ARRAY' ){
        if( ref $size_ranges eq 'HASH' ){
            # check keys
            confess "HAVEN'T IMPLEMENTED THIS YET!\n";
        }
        else{
            confess "The second argument must be a ArrayRef not ",
                ref $size_ranges, ".\n";
        }
    }
    
    if( !$adaptors_for ){
        confess "Ensembl Adaptors must be supplied.\n";
    }
    elsif( !ref $adaptors_for || ref $adaptors_for ne 'HASH' ){
        confess "The third argument must be a HashRef not ",
            ref $adaptors_for, ".\n";
    }
    
    foreach my $size_ranges ( @{$size_ranges} ){
        my $ext_range = $size_ranges->{ext};
        my $int_range = $size_ranges->{int};
        
        #find out what the default excluded region is so it can be reset
        my $excluded_defaults;
        foreach my $id ( keys %$targets ){
            $excluded_defaults->{$id} = $targets->{$id}->{ext_amp}[5];
        }
        # DESIGN PRIMERS
        ##  EXTERNAL PRIMERS - ROUND 1 ##
        my $round = 1;
        $targets = $self->design_primers($targets, 'ext', $ext_range, 6, $round, 1, 1, $adaptors_for, 1, );
        $round++;
        
        ##  EXTERNAL PRIMERS - ROUND 2 ##
        foreach my $id ( keys %$targets) {
            if (!defined $targets->{$id}->{ext_primers}) {
                $targets->{$id}->{ext_amp}[5] = $excluded_defaults->{$id};
            }
        }
        $targets = $self->design_primers($targets, 'ext', $ext_range, 6, $round, 0, 1, $adaptors_for, 1, );
        $round++;
        
        ##  EXTERNAL PRIMERS - ROUND 3 ##
        foreach my $id ( keys %$targets) {
            if (!defined $targets->{$id}->{ext_primers}) {
                $targets->{$id}->{ext_amp}[5] = $excluded_defaults->{$id};
            }
        }
        $targets = $self->design_primers($targets, 'ext', $ext_range, 6, $round, 0, 0, $adaptors_for, 1, );
        $round++;
        
        foreach my $id ( sort keys %{$targets} ){
            if( !defined $targets->{$id}->{'ext_primers'} ){
                warn "Unable to design primers for target $id", "\n";
            }
            else{
                # get new design slice to match external primers
                my $species = $targets->{$id}->{'species'};
                my $slice_adaptor = $adaptors_for->{$species}->{'sa'};
                my $slice = $slice_adaptor->fetch_by_region( 'toplevel',
                $targets->{ $id }->{chr}, $targets->{ $id }->{ext_start},
                $targets->{ $id }->{ext_end}, $targets->{ $id }->{strand} );
                
                $targets->{ $id }->{design_slice} = $slice;
            }
        }
        
        ##  INTERNAL PRIMERS - ROUND 1 ##
        $excluded_defaults = {};
        foreach my $id (sort keys %$targets) {
            if (defined $targets->{$id}->{ext_primers}
                && !defined $targets->{$id}->{int_primers}) {
                $targets->{$id}->{int_start}    = $targets->{$id}->{ext_start};
                $targets->{$id}->{int_end}      = $targets->{$id}->{ext_end};
                my $ext_p    = $targets->{$id}->{ext_primers};
                my ( $target_start, $target_end );
                if( $targets->{$id}->{strand} eq '1' ){
                    $target_start = $targets->{$id}->{start} - ($targets->{$id}->{int_start} - 1);
                    $target_end = $targets->{$id}->{end} - ($targets->{$id}->{int_start} - 1);
                }
                if( $targets->{$id}->{strand} eq '-1' ){
                    $target_start = $targets->{$id}->{int_end} - ($targets->{$id}->{end} - 1);
                    $target_end = $targets->{$id}->{int_end} - ($targets->{$id}->{start} - 1);
                }
                $targets->{$id}->{int_amp} = [
                    $id,
                    $targets->{$id}->{design_slice}->seq,
                    undef,
                    undef,
                    [ [ $target_start, $target_end - ( $target_start - 1 ) ] ], #target
                    [ [  $target_start - 10, $target_end - ( $target_start - 1 ) + 20 ], ],
                    undef,
                    ];
                $excluded_defaults->{$id} = $targets->{$id}->{int_amp}[5];
                push @{$targets->{$id}->{int_amp}[5]},
                    [ 0, $ext_p->left_primer->length - 10 ],
                    [ $ext_p->product_size - 10, 10 ];
            }
        }
        $round = 1;
        $targets = $self->design_primers($targets, 'int', $int_range, 6, $round, 1, 1, $adaptors_for, 1, );
        $round++;
        
        ##  INTERNAL PRIMERS - ROUND 2 ##
        foreach my $id (sort keys %$targets) {
            if (defined $targets->{$id}->{ext_primers}
                && !defined $targets->{$id}->{int_primers}) {
                $targets->{$id}->{int_amp}[5] = $excluded_defaults->{$id};
            }
        }
        $targets = $self->design_primers($targets, 'int', $int_range, 6, $round, 1, 1, $adaptors_for, 1, );
        $round++;
        
        ##  INTERNAL PRIMERS - ROUND 3 ##
        foreach my $id (sort keys %$targets) {
            if (defined $targets->{$id}->{ext_primers}
                && !defined $targets->{$id}->{int_primers}) {
                $targets->{$id}->{int_amp}[5] = $excluded_defaults->{$id};
            }
        }
        
        $targets = $self->design_primers($targets, 'int', $int_range, 9, $round, 1, 1, $adaptors_for, 1, );
        $round++;
        
        ##  INTERNAL PRIMERS - ROUND 4 ##
        foreach my $id (sort keys %$targets) {
            if (defined $targets->{$id}->{ext_primers}
                && !defined $targets->{$id}->{int_primers}) {
                $targets->{$id}->{int_amp}[5] = $excluded_defaults->{$id};
            }
        }
        $targets = $self->design_primers($targets, 'int', $int_range, 2, $round, 1, 1, $adaptors_for, 1, );
        $round++;
        
        ##  INTERNAL PRIMERS - ROUND 5 ##
        foreach my $id (sort keys %$targets) {
            if (defined $targets->{$id}->{ext_primers}
                && !defined $targets->{$id}->{int_primers}) {
                $targets->{$id}->{int_amp}[5] = $excluded_defaults->{$id};
            }
        }
        $targets = $self->design_primers($targets, 'int', $int_range, 6, $round, 0, 1, $adaptors_for, 1, );
        $round++;
        
        ##  INTERNAL PRIMERS - ROUND 6 ##
        foreach my $id (sort keys %$targets) {
            if (defined $targets->{$id}->{ext_primers}
                && !defined $targets->{$id}->{int_primers}) {
                $targets->{$id}->{int_amp}[5] = $excluded_defaults->{$id};
            }
        }
        
        $targets = $self->design_primers($targets, 'int', $int_range, 9, $round, 0, 1, $adaptors_for, 1, );
        $round++;
        
        ##  INTERNAL PRIMERS - ROUND 7 ##
        foreach my $id (sort keys %$targets) {
            if (defined $targets->{$id}->{ext_primers}
                && !defined $targets->{$id}->{int_primers}) {
                $targets->{$id}->{int_amp}[5] = $excluded_defaults->{$id};
            }
        }
        $targets = $self->design_primers($targets, 'int', $int_range, 2, $round, 0, 1, $adaptors_for, 1, );
        $round++;
        
        ##  INTERNAL PRIMERS - ROUND 8 ##
        foreach my $id (sort keys %$targets) {
            if (defined $targets->{$id}->{ext_primers}
                && !defined $targets->{$id}->{int_primers}) {
                $targets->{$id}->{int_amp}[5] = $excluded_defaults->{$id};
            }
        }
        $targets = $self->design_primers($targets, 'int', $int_range, 6, $round, 0, 0, undef, 1, );
        $round++;
        
        ##  INTERNAL PRIMERS - ROUND 9 ##
        $targets = $self->design_primers($targets, 'int', $int_range, 9, $round, 0, 0, undef, 1, );
        $round++;
        
        ##  INTERNAL PRIMERS - ROUND 10 ##
        $targets = $self->design_primers($targets, 'int', $int_range, 2, $round, 0, 0, undef, 1, );
        $round++;
        
        ##  INTERNAL PRIMERS - ROUND 11 ##
        foreach my $id (sort keys %$targets) {
            if (defined $targets->{$id}->{ext_primers}
                && !defined $targets->{$id}->{int_primers}) {
                $targets->{$id}->{int_amp}[5] = [];
            }
        }
        $targets = $self->design_primers($targets, 'int', $int_range, 6, $round, 0, 0, undef, 1, );
        $round++;
        
        ##  INTERNAL PRIMERS - ROUND 12 ##
        $targets = $self->design_primers($targets, 'int', $int_range, 9, $round, 0, 0, undef, 1, );
        $round++;
        
        ##  INTERNAL PRIMERS - ROUND 13 ##
        $targets = $self->design_primers($targets, 'int', $int_range, 2, $round, 0, 0, undef, 1, );
        $round++;
        
        #if( $debug ){
        #    foreach my $id ( sort keys %{$targets} ){
        #        print join("\t", $targets->{$id}->{'int_start'},
        #                   $targets->{$id}->{'int_end'},
        #                   $targets->{$id}->{'int_primers'}->left_primer->index_pos,
        #                   $targets->{$id}->{'int_primers'}->product_size,
        #                   ), "\n",
        #                   $targets->{$id}->{'int_primers'}->left_primer->seq, "\n",
        #                   $targets->{$id}->{'int_primers'}->right_primer->seq, "\n",
        #                    ;
        #    }
        #}
        #
    }
    return $targets;
}

=method design_primers_multiple_rounds

  Usage       : $crispr_design->design_primers_multiple_rounds( \%targets, $type, \@size_ranges, \%adaptors_for );
  Purpose     : Designs PCR primers using multiple rounds
  Returns     : Hashref of primers and settings
  Parameters  : HashRef of target info and settings
                Str (primer type)
                ArrayRef of Str (product size ranges)
                HashRef of Bio::EnsEMBL::DBSQL::SliceAdaptor and
                Bio::EnsEMBL::DBSQL::VariationFeatureAdaptor adaptors for
                particular species (e.g. $hashref->{species}->{sa || vfa})
  Throws      : 
  Comments    : 

=cut

sub design_primers_multiple_rounds {
    my ( $self, $targets, $type, $size_ranges, $adaptors_for ) = @_;
    
    foreach my $size_range ( @{$size_ranges} ){
        #find out what the default excluded region is so it can be reset
        my $excluded_defaults;
        foreach my $id ( keys %$targets ){
            $excluded_defaults->{$id} = $targets->{$id}->{$type . '_amp'}[5];
        }
        
        my $round = 1;
        $targets = $self->design_primers($targets, $type, $size_range, 9, $round, 1, 1, $adaptors_for, 1, );
        $round++;
        
        ##  NEXT ROUND  ##
        foreach my $id (sort keys %$targets) {
            if (defined $targets->{$id}->{$type . '_primers'}
                && !defined $targets->{$id}->{$type . '_primers'}) {
                $targets->{$id}->{$type . '_amp'}[5] = $excluded_defaults->{$id};
            }
        }
        $targets = $self->design_primers($targets, $type, $size_range, 6, $round, 1, 1, $adaptors_for, 1, );
        $round++;
        
        ##  NEXT ROUND  - NO REPEAT MASK  ##
        foreach my $id (sort keys %$targets) {
            if (defined $targets->{$id}->{$type . '_primers'}
                && !defined $targets->{$id}->{$type . '_primers'}) {
                $targets->{$id}->{$type . '_amp'}[5] = $excluded_defaults->{$id};
            }
        }
        $targets = $self->design_primers($targets, $type, $size_range, 9, $round, 0, 1, $adaptors_for, 1, );
        $round++;
        
        ##  NEXT ROUND  - NO REPEAT MASK  ##
        foreach my $id (sort keys %$targets) {
            if (defined $targets->{$id}->{$type . '_primers'}
                && !defined $targets->{$id}->{$type . '_primers'}) {
                $targets->{$id}->{$type . '_amp'}[5] = $excluded_defaults->{$id};
            }
        }
        $targets = $self->design_primers($targets, $type, $size_range, 6, $round, 0, 1, $adaptors_for, 1, );
        $round++;
        
        ##  NEXT ROUND  - NO VARIATION MASK  ##
        foreach my $id (sort keys %$targets) {
            if (defined $targets->{$id}->{$type . '_primers'}
                && !defined $targets->{$id}->{$type . '_primers'}) {
                $targets->{$id}->{$type . '_amp'}[5] = $excluded_defaults->{$id};
            }
        }
        $targets = $self->design_primers($targets, $type, $size_range, 9, $round, 0, 0, undef, 1, );
        $round++;
        
        ##  NEXT ROUND  - NO VARIATION MASK  ##
        foreach my $id (sort keys %$targets) {
            if (defined $targets->{$id}->{$type . '_primers'}
                && !defined $targets->{$id}->{$type . '_primers'}) {
                $targets->{$id}->{$type . '_amp'}[5] = $excluded_defaults->{$id};
            }
        }
        $targets = $self->design_primers($targets, $type, $size_range, 6, $round, 0, 0, undef, 1, );
        $round++;
        
    }
    
    return $targets;
}

=method sort_and_select_primers

  Usage       : $crispr_design->sort_and_select_primers( \@primers, $type, $round, \%targets, \%adaptors_for, $restriction_digest);
  Purpose     : Selects primers by pair_penalty (then product size)
  Returns     : Hashref of primers and settings
  Parameters  : Primers to sort (ArrayRef of PrimerPair objects)
                Primer type (Str)
                Product size ranges (ArrayRef of Str)
                Primer Design round (Int)
                HashRef of target info and settings
                HashRef of Bio::EnsEMBL::DBSQL::SliceAdaptor and
                Bio::EnsEMBL::DBSQL::VariationFeatureAdaptor adaptors for
                particular species (e.g. $hashref->{species}->{sa || vfa})
                Restriction digest flag (Int)
  Throws      : 
  Comments    : 

=cut

sub sort_and_select_primers {
    my ( $self, $primers_to_sort, $type, $round, $targets, $adaptors_for, $re ) = @_;
    
    my @primers = grep {
            $_->left_primer->seq &&
            $_->right_primer->seq &&
            !defined $targets->{$_->amplicon_name}->{$type . '_primers'}
        } @{$primers_to_sort};
    
    foreach my $primer_pair (sort {$a->amplicon_name cmp $b->amplicon_name
                              || $a->pair_penalty <=> $b->pair_penalty
                              || $a->product_size <=> $b->product_size } @primers ) {
        my $id = $primer_pair->amplicon_name;
        #print STDERR join("\t",
        #    $id,
        #    $targets->{$id}->{$type . '_start'} + $primer->left_primer->index_pos,
        #    $targets->{$id}->{$type . '_start'} + $primer->left_primer->index_pos + $primer->product_size - 1,
        #    $primer->variants_in_pcr_product,
        #), "\n";
        
        if ($primer_pair->left_primer->seq && $primer_pair->right_primer->seq
            && !defined $targets->{$id}->{$type . '_primers'}) {
                $targets->{$id}->{$type . '_primers'}  = $primer_pair;
                $targets->{$id}->{$type . '_round'}    = $round;
                $primer_pair->type( $type );
                if( $type eq 'int' && $re ){
                    ( undef, $targets->{$id}, ) =
                        $self->check_for_unique_re_in_amplicon_and_crRNAs( $primer_pair, $type, $targets->{$id}, $id, $adaptors_for );
                    # call uniq_in_both to check for overlapping sites
                    # check whether this design is for a Crispr::Pair or single crRNA
                    if( exists $targets->{$id}->{crispr_pair} && $targets->{$id}->{crispr_pair} ){
                        foreach my $crRNA ( @{ $targets->{$id}->{crispr_pair}->crRNAs } ){
                            $crRNA->unique_restriction_sites->uniq_in_both();
                        }
                    }
                    elsif( exists $targets->{$id}->{crRNA} && $targets->{$id}->{crRNA} ){
                        $targets->{$id}->{crRNA}->unique_restriction_sites->uniq_in_both();
                    }
                    
                }
            #next if $type eq 'hrm';
            if( $targets->{$id}->{strand} eq '1' ){
                # start and end
                $targets->{$id}->{$type . '_start'}    = $targets->{$id}->{$type . '_start'} + $primer_pair->left_primer->index_pos;
                $targets->{$id}->{$type . '_end'}      = $targets->{$id}->{$type . '_start'} + ( $primer_pair->product_size - 1 );
                
                # left primer start and end
                $targets->{$id}->{$type . '_primers'}->left_primer->seq_region_start( $targets->{$id}->{$type . '_start'} );
                $targets->{$id}->{$type . '_primers'}->left_primer->seq_region_end( $targets->{$id}->{$type . '_start'} +
                                                        ( $targets->{$id}->{$type . '_primers'}->left_primer->length - 1 ) );
                $targets->{$id}->{$type . '_primers'}->left_primer->seq_region_strand( '1' );
                
                # right primer start and end
                $targets->{$id}->{$type . '_primers'}->right_primer->seq_region_start(
                    ( $targets->{$id}->{$type . '_end'} -
                        ($targets->{$id}->{$type . '_primers'}->right_primer->length - 1) ) );
                $targets->{$id}->{$type . '_primers'}->right_primer->seq_region_end( $targets->{$id}->{$type . '_end'} );
                $targets->{$id}->{$type . '_primers'}->right_primer->seq_region_strand( '-1' );
                
            }
            if( $targets->{$id}->{strand} eq '-1' ){
                # start and end
                $targets->{$id}->{$type . '_end'}    = $targets->{$id}->{$type . '_end'} - $primer_pair->left_primer->index_pos;
                $targets->{$id}->{$type . '_start'}      = $targets->{$id}->{$type . '_end'} - ( $primer_pair->product_size - 1 );
                
                # left primer start and end
                $targets->{$id}->{$type . '_primers'}->left_primer->seq_region_end( $targets->{$id}->{$type . '_end'} );
                $targets->{$id}->{$type . '_primers'}->left_primer->seq_region_start( $targets->{$id}->{$type . '_end'} -
                                                        ( $targets->{$id}->{$type . '_primers'}->left_primer->length - 1 ) );
                $targets->{$id}->{$type . '_primers'}->left_primer->seq_region_strand( '-1' );
                
                # right primer start and end
                $targets->{$id}->{$type . '_primers'}->right_primer->seq_region_start( $targets->{$id}->{$type . '_start'} );
                $targets->{$id}->{$type . '_primers'}->right_primer->seq_region_end( $targets->{$id}->{$type . '_start'} +
                                                        ( $targets->{$id}->{$type . '_primers'}->right_primer->length - 1 ) );
                $targets->{$id}->{$type . '_primers'}->right_primer->seq_region_strand( '1' );
                
            }
            $targets->{$id}->{$type . '_primers'}->left_primer->seq_region( $targets->{$id}->{chr} );
            $targets->{$id}->{$type . '_primers'}->right_primer->seq_region( $targets->{$id}->{chr} );
            
            $targets->{$id}->{$type . '_primers'}->left_primer->primer_name(
                join(":", $targets->{$id}->{chr} || '',
                join("-", $targets->{$id}->{$type . '_primers'}->left_primer->seq_region_start,
                    $targets->{$id}->{$type . '_primers'}->left_primer->seq_region_end, ),
                $targets->{$id}->{$type . '_primers'}->left_primer->seq_region_strand )
            );
            $targets->{$id}->{$type . '_primers'}->right_primer->primer_name(
                join(":", $targets->{$id}->{chr} || '',
                join("-", $targets->{$id}->{$type . '_primers'}->right_primer->seq_region_start,
                    $targets->{$id}->{$type . '_primers'}->right_primer->seq_region_end, ),
                $targets->{$id}->{$type . '_primers'}->right_primer->seq_region_strand )
            );
            
            $targets->{$id}->{$type . '_primers'}->pair_name(
            join(":", $targets->{$id}->{chr} || '',
                        join("-", $targets->{$id}->{$type . '_start'}, $targets->{$id}->{$type . '_end'}, ),
                        $targets->{$id}->{strand} || '1',
                        $targets->{$id}->{$type . '_round'}, )
            );
            
        }
    }
    
    return $targets;
}

=method fasta_for_repeatmask

  Usage       : $crispr_design->fasta_for_repeatmask( \%targets, $type );
  Purpose     : Produces a fasta file of sequences for repeat masking
  Returns     : Target sequences (ArrayRef of Str)
  Parameters  : HashRef of target info and settings
                Primer type (Str)
  Throws      : 
  Comments    : 

=cut

sub fasta_for_repeatmask {
    my ( $self, $targets, $type ) = @_;
    
    my $amp_array = [];
    
    open my $fasta_fh, '>', 'RM_' . $type . '.fa';
    foreach my $id (sort keys %$targets) {
        if (defined $targets->{$id}->{"${type}_amp"}
            && !defined $targets->{$id}->{"${type}_primers"}) {
            my $amp = $targets->{$id}->{"${type}_amp"};
            print {$fasta_fh} '>', $amp->[0], "\n", $amp->[1], "\n";
            push(@$amp_array, $amp);
        }
    }
    close($fasta_fh);
    return $amp_array;
}

=method repeatmask

  Usage       : $crispr_design->repeatmask( \%targets, $type );
  Purpose     : Runs repeat masking
  Returns     : Targets HashRef
  Parameters  : Hashref of target info and settings
                Primer type (Str)
  Throws      : 
  Comments    : 

=cut

sub repeatmask {
    my ($self, $targets, $type ) = @_;
    
    my $cmd = '/software/pubseq/bin/RepeatMasker -xsmall -int ' . 'RM_' . $type . '.fa';
    my $pid = system($cmd);
    
    if (-f 'RM_' . $type . '.fa.out') {
        open my $rm_fh, '<', 'RM_' . $type . '.fa.out' or die "Can't open RM_", $type, ".fa.out: $!\n";
        while (<$rm_fh>) {
            chomp;
            my @line = split(/\s+/, $_);
            next unless @line && $line[1] =~ m/^\d+$/; # Score
            my $id = $line[5]; # ID
            push @{ $targets->{$id}->{$type . '_amp'}[5] }, [ $line[6], $line[7] - $line[6] ]; # Start and end
        }
        close($rm_fh);
    }
    
    my @rmfile = (
        'RM_' . $type . '.fa',
        'RM_' . $type . '.fa.ref',
        'RM_' . $type . '.fa.out',
        'RM_' . $type . '.fa.cat',
        'RM_' . $type . '.fa.masked',
        'RM_' . $type . '.fa.tbl',
        'RM_' . $type . '.fa.log',
        'RM_' . $type . '.fa.cat.all',
        'setdb.log',
    );
    unlink @rmfile;
    return $targets;
}

=method variationmask

  Usage       : $crispr_design->variationmask( \%targets, $type, \%adaptors_for, );
  Purpose     : Searches Ensembl databases for variation to avoid
  Returns     : Targets HashRef
  Parameters  : Hashref of target info and settings
                Primer type (Str)
                HashRef of Bio::EnsEMBL::DBSQL::SliceAdaptor and
                Bio::EnsEMBL::DBSQL::VariationFeatureAdaptor adaptors for
                particular species (e.g. $hashref->{species}->{sa || vfa})
  Throws      : 
  Comments    : 

=cut

sub variationmask {
    my ( $self, $targets, $type, $adaptors_for, ) = @_;
    
    foreach my $id (sort keys %$targets) {
        next if( !defined $targets->{$id}->{$type . '_start'} ||
                !defined $targets->{$id}->{$type . '_end'} );
        my $species = $targets->{$id}->{'species'};
        my $slice_adaptor = $adaptors_for->{$species}->{'sa'};
        my $vfa = $adaptors_for->{$species}->{'vfa'};
        # get slice
        my $slice = $slice_adaptor->fetch_by_region( 'toplevel',
                    $targets->{$id}->{chr}, $targets->{$id}->{$type . '_start'},
                    $targets->{$id}->{$type . '_end'}, $targets->{$id}->{strand}, );
        #my $slice_length = $slice->length;
        my $vfs = $vfa->fetch_all_by_Slice($slice);
        my %vf_seen;
        foreach my $vf ( @{$vfs} ){
            #check if we've seen this before
            my $vf_key = $vf->seq_region_start() . '-' . $vf->seq_region_end() . '-' . $vf->allele_string();
            next if( exists $vf_seen{ $vf_key } );
            $vf_seen{ $vf_key } = 1;
            
            my $var = $vf->variation();
            if ($vf->var_class eq 'SNP') {
                push @{ $targets->{$id}->{$type . '_amp'}[5] },
                    [ $vf->start, $vf->end - ( $vf->start - 1) ];
            }
            elsif ($vf->var_class eq 'deletion') {
                # Ensure deletions don't extend out of slice
                my $start = $vf->seq_region_start();
                my $end   = $vf->seq_region_end();
                $start = 1 if $start < $targets->{$id}->{$type . '_start'};
                $end   = $vf->end if $end > $targets->{$id}->{$type . '_end'};
                push @{ $targets->{$id}->{$type . '_amp'}[5] },
                    [ $vf->start, $vf->end - ( $vf->start - 1) ];
            }
            elsif ($vf->var_class eq 'insertion') {
                my @alleles = split(/\//, $vf->allele_string());
                my $length = 0;
                foreach my $allele (@alleles) {
                    if ($allele ne '-' && length($allele) > $length) {
                        $length = length($allele);
                    }
                }
                push @{ $targets->{$id}->{$type . '_amp'}[5] },
                    [ $vf->start, $vf->start - ( $vf->end - 1 ) ];
            }
        }
    }
    
    return $targets;
}


=func get_design_slice_for_target

  Usage       : $design_slice = get_design_slice_for_target( $target, $slice_adaptor, $slice_extender );
  Purpose     : get a slice for designing PCR primers for a target 
  Returns     : Bio::EnsEMBL::Slice
  Parameters  : Crispr::Target
                Bio::EnsEMBL::DBSQL::SliceAdaptor
                A number of bases to extend the slice by (optional:default=700)
  Throws      : If 1st arg is not a Crispr::Target
                If 2nd arg is not a Bio::EnsEMBL::DBSQL::SliceAdaptor
  Comments    : None

=cut

sub get_design_slice_for_target {
    my ( $self, $target, $slice_adaptor, $slice_extender ) = @_;
    if( !$target ){
        confess "A Crispr::Target object must be supplied.\n";
    }
    elsif( !ref $target || !$target->isa('Crispr::Target') ){
        confess "The first argument must be a Crispr::Target object not ",
            ref $target, ".\n";
    }
    
    if( !$slice_adaptor ){
        confess "Cannot get slice wthout slice adaptor.\n";
    }
    elsif( !ref $slice_adaptor || !$slice_adaptor->isa('Bio::EnsEMBL::DBSQL::SliceAdaptor') ){
        confess "The second argument must be a Bio::EnsEMBL::DBSQL::SliceAdaptor object not ",
            ref $target, ".\n";
    }
    
    if( !$slice_extender ){
        $slice_extender = 700;
    }
    # get slice for target region
    my $slice = $slice_adaptor->fetch_by_region( 'toplevel',
        $target->chr, $target->start, $target->end, $target->strand, );
    
    my $design_slice;
    $design_slice = $slice->expand($slice_extender, $slice_extender);
    
    # Check for truncated slices because don't yet handle them properly.
    check_slice( $design_slice, $target->length, $slice_extender, );
    
    # Trim to avoid Ns
    my $start = $design_slice->start;
    my $end = $design_slice->end;
    while ($design_slice->seq =~ m/N+/g) {
        my $slice_start = $design_slice->start;
        my $slice_end = $design_slice->end;
        my $ns   = length($&);
        my $spos = length($`);
        my $epos = $spos + $ns;
        my $g_spos = $slice_start + $spos - 1;
        my $g_epos = $g_spos + $ns;
        my ($shift_end_left, $shift_start_left, $shift_start_right, $shift_end_right);
        if ($g_spos > $target->end && (length($') < 30 || $ns > 2)) {
            $shift_end_left = -(length($') + $ns);
            $shift_start_left  = length($') + $ns if $slice_start == $start;
            $design_slice = $design_slice->expand($shift_start_left, $shift_end_left, 1);
        } elsif ($g_spos < $target->start && ($spos < 30 || $ns > 2)) {
            $shift_start_right = -$epos;
            $shift_end_right = $epos if $slice_end == $end;
            $design_slice = $design_slice->expand($shift_start_right, $shift_end_right, 1);
        }
    }
    
    return $design_slice;
}

=method check_slice

  Usage       : $crispr_design->check_slice( $slice, $spacer_target_length, $slice_extender );
  Purpose     : Check that slice is the right size
  Returns     : None
  Parameters  : Slice object (Bio::EnsEMBL::Slice)
                target length (Int)
                A number of bases to extend the slice by (Int)
  Throws      : 
  Comments    : 

=cut

sub check_slice {
    my ( $self, $slice, $target_length, $slice_extender ) = @_;
    my $seq = $slice->seq();
    print STDERR 'Slice for ', $slice->name(), " is truncated.\n"
        if length($seq) != $target_length + 2*$slice_extender;
}

=method check_for_unique_re_in_amplicon_and_crRNAs

  Usage       : $crispr_design->check_for_unique_re_in_amplicon_and_crRNAs( $primer_pair, $type, \%target_info, $id, \%adaptors_for );
  Purpose     : Checks whether there are restriction enzyme cut sites that are
                in the crispr target site and unique in the PCR amplicon
  Returns     : OK flag (0 or 1)
                Target info (HashRef of target info and settings)
  Parameters  : Primer pair (Crispr::PrimerPair)
                Primer type (Str)
                Target info (HashRef of targets info and settings)
                Id (Str)
                HashRef of Bio::EnsEMBL::DBSQL::SliceAdaptor and
                Bio::EnsEMBL::DBSQL::VariationFeatureAdaptor adaptors for
                particular species (e.g. $hashref->{species}->{sa || vfa})
  Throws      : 
  Comments    : 

=cut

sub check_for_unique_re_in_amplicon_and_crRNAs {
    my ( $self, $primer_pair, $type, $target_info, $id, $adaptors_for ) = @_;
    my $ok = 0;
    
    my $enzymes = $self->enzyme_collection;
    my $amplicon_seq = substr(
        $target_info->{ $type . '_amp'}->[1],
        $primer_pair->left_primer->index_pos,
        $primer_pair->product_size,
    );
    
    my $amplicon = Bio::PrimarySeq->new(
        -seq => $amplicon_seq,
        -primary_id => $primer_pair->amplicon_name,
        -molecule => 'dna'
    );
    my $amplicon_re_analysis = Bio::Restriction::Analysis->new(
        -seq => $amplicon,
        -enzymes => $enzymes,
    );
    my $uniq_cutters = $amplicon_re_analysis->unique_cutters;
    
    # check whether this design is for a Crispr::Pair or single crRNA
    if( exists $target_info->{crispr_pair} && $target_info->{crispr_pair} ){
        foreach my $crRNA ( @{ $target_info->{crispr_pair}->crRNAs } ){
            ( my $has_re, $crRNA ) = $self->compare_amplicon_to_crRNA( $target_info, $id, $amplicon_re_analysis, $crRNA, $adaptors_for, );
            $ok = $ok | $has_re;
        }
    }
    elsif( exists $target_info->{crRNA} && $target_info->{crRNA} ){
        my $crRNA = $target_info->{crRNA};
        ( $ok, $crRNA ) = $self->compare_amplicon_to_crRNA( $target_info, $id, $amplicon_re_analysis, $crRNA, $adaptors_for, );
    }
    
    return ( $ok, $target_info );
}

=method compare_amplicon_to_crRNA

  Usage       : $crispr_design->compare_amplicon_to_crRNA( \%target_info, $id, $amplicon_re_analysis, $crRNA, \%adaptors_for );
  Purpose     : Compares to Restriction::Analysis objects to check for unique
                restriction enzyme sites
  Returns     : OK flag (0 or 1)
                Crispr::crRNA object
  Parameters  : Target info (HashRef of targets info and settings)
                Id (Str)
                Amplicon Restriction Analysis (Bio::Restriction::Analysis)
                Crispr (Crispr::crRNA)
                HashRef of Bio::EnsEMBL::DBSQL::SliceAdaptor and
                Bio::EnsEMBL::DBSQL::VariationFeatureAdaptor adaptors for
                particular species (e.g. $hashref->{species}->{sa || vfa})
  Throws      : 
  Comments    : 

=cut

sub compare_amplicon_to_crRNA {
    my ( $self, $target_info, $id, $amplicon_re_analysis, $crRNA, $adaptors_for ) = @_;
    
    my $ok = 0;
    my $enzymes = $self->enzyme_collection;
    # get slice for crRNA
    my $crRNA_slice = $adaptors_for->{ $target_info->{species} }->{sa}->fetch_by_region('toplevel', $crRNA->chr, $crRNA->start, $crRNA->end, $crRNA->strand, );
    
    # expand slice by 15 bp downstream of cut-site
    my ( $left_expand, $right_expand ) = ( 0, 15 );
    # check that this would not go off the chromosome and adjust if necessary
    if( $crRNA->{strand} eq '1' && $crRNA_slice->seq_region_length - $crRNA_slice->end < 15 ){
        $right_expand = $crRNA_slice->seq_region_length - $crRNA_slice->end;
    } elsif( $crRNA->{strand} eq '-1' && $crRNA_slice->start - 1 < 15 ){
        $right_expand = $crRNA_slice->start - 1;
    }
    my $slice_for_re = $crRNA_slice->expand( $left_expand, $right_expand );
    my $crRNA_seq = Bio::PrimarySeq->new(
        -seq => $slice_for_re->seq,
        -primary_id => $id,
        -molecule => 'dna'
    );
    my $crRNA_re_analysis = Bio::Restriction::Analysis->new(
        -seq => $crRNA_seq,
        -enzymes => $enzymes,
    );
    my $uniq_in_crRNA = $crRNA_re_analysis->unique_cutters;
    
    # compare the two lists
    my $uniq_in_both  = Bio::Restriction::EnzymeCollection->new( -empty => 1 );
    
    foreach my $enzyme ( $uniq_in_crRNA->each_enzyme ){
        if( any { $enzyme->name eq $_->name } $amplicon_re_analysis->unique_cutters->each_enzyme ){
            my ( $vendors, ) = $enzyme->vendors;
            if( any { $_ eq 'N' } @{$vendors} ){
                $uniq_in_both->enzymes( $enzyme );
                $ok = 1;
            }
        }
    }
    # make a new EnzymeInfo object
    my $enzyme_info = Crispr::EnzymeInfo->new(
        analysis => $crRNA_re_analysis,
        amplicon_analysis => $amplicon_re_analysis,
        uniq_in_both => $uniq_in_both,
    );
    $crRNA->unique_restriction_sites( $enzyme_info );
    
    return ( $ok, $crRNA );
}

=method primers_header

  Usage       : $crispr_design->primers_header;
  Purpose     : Returns a list of column names for primers
  Returns     : Array
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub primers_header {
    my ( $self, ) = @_;
    my @info = ( qw{ chromosome target_position strand amp_size round
        pair_name left_id left_seq right_id right_seq
        length1 tm1 length2 tm2 } );
    return @info;
}

=method print_primers_to_file

  Usage       : $crispr_design->print_primers_to_file( \%targets, $type, $primer_fh );
  Purpose     : Prints primer info to a file_handle
  Returns     : 1 on Success
  Parameters  : Target info (HashRef)
                Primer type (Str)
                File Handle
  Throws      : 
  Comments    : 

=cut

sub print_primers_to_file {
    my ( $self, $targets, $type, $primer_fh ) = @_;
    
    foreach my $target_info ( @{$targets} ){
        if (defined $target_info->{$type . '_primers'}) {
            print $primer_fh join("\t",
                $target_info->{chr},
                join("-", $target_info->{start},
                     $target_info->{end} ),
                $target_info->{strand},
                $target_info->{$type . '_primers'}->product_size,
                $target_info->{$type . '_round'},
                $target_info->{$type . '_primers'}->pair_name,
                $target_info->{$type . '_primers'}->left_primer->primer_name,
                $target_info->{$type . '_primers'}->left_primer->seq,
                $target_info->{$type . '_primers'}->right_primer->primer_name,
                $target_info->{$type . '_primers'}->right_primer->seq,
                $target_info->{$type . '_primers'}->left_primer->length,
                $target_info->{$type . '_primers'}->left_primer->tm,
                $target_info->{$type . '_primers'}->right_primer->length,
                $target_info->{$type . '_primers'}->right_primer->tm,
            ), "\n";
        }
        else {
            print $primer_fh join("\t",
                $target_info->{chr},
                join("-", $target_info->{start},
                     $target_info->{end} ),
                $target_info->{strand},
                'NO PRIMERS',
            ), "\n";
        }
    }
    
    return 1;
}

=method nested_primers_header

  Usage       : $crispr_design->nested_primers_header;
  Purpose     : Returns a list of column names for nested primers
  Returns     : Array
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub nested_primers_header {
    my ( $self, ) = @_;
    return join("\t",
    'chromosome', 'target_position', 'strand',
    'ext_amp_size', 'int_amp_size',
    'ext_round', 'int_round',
    'ext_pair_name', 'int_pair_name',
    'ext_left_id', 'ext_left_seq',
    'int_left_id', 'int_left_seq',
    'int_right_id', 'int_right_seq',
    'ext_right_id', 'ext_right_seq',
    'length1', 'tm1',
    'length2', 'tm2',
    'length3', 'tm3',
    'length4', 'tm4',
    ), "\n";
}

=method print_nested_primers_to_file

  Usage       : $crispr_design->print_nested_primers_to_file( \%targets, $primer_fh );
  Purpose     : Prints info about nested primers to a file handle
  Returns     : None
  Parameters  : Target info (HashRef)
                File Handle
  Throws      : 
  Comments    : 

=cut

sub print_nested_primers_to_file {
    my ( $self, $targets, $primer_fh ) = @_;
    
    #my $row = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',];
    #my $col = [1..12];
    #my ($coli, $rowi, $plate) = (0,0,1);
    #
    foreach my $target_info ( @{$targets} ){
        if (defined $target_info->{ext_primers}) {
            if (defined $target_info->{int_primers}) {
                
                print $primer_fh join("\t",
                    $target_info->{chr},
                    join("-", $target_info->{start},
                         $target_info->{end} ),
                    $target_info->{strand},
                    $target_info->{ext_primers}->product_size,
                    $target_info->{int_primers}->product_size,
                    $target_info->{ext_round},
                    $target_info->{int_round},
                    $target_info->{ext_primers}->pair_name,
                    $target_info->{int_primers}->pair_name,
                    $target_info->{ext_primers}->left_primer->primer_name,
                    $target_info->{ext_primers}->left_primer->seq,
                    $target_info->{int_primers}->left_primer->primer_name,
                    $target_info->{int_primers}->left_primer->seq,
                    $target_info->{int_primers}->right_primer->primer_name,
                    $target_info->{int_primers}->right_primer->seq,
                    $target_info->{ext_primers}->right_primer->primer_name,
                    $target_info->{ext_primers}->right_primer->seq,
                    $target_info->{ext_primers}->left_primer->length,
                    $target_info->{ext_primers}->left_primer->tm,
                    $target_info->{int_primers}->left_primer->length,
                    $target_info->{int_primers}->left_primer->tm,
                    $target_info->{int_primers}->right_primer->length,
                    $target_info->{int_primers}->right_primer->tm,
                    $target_info->{ext_primers}->right_primer->length,
                    $target_info->{ext_primers}->right_primer->tm,
                ), "\n";
            }
            else {
                print $primer_fh join("\t",
                    $target_info->{chr},
                    join("-", $target_info->{start},
                         $target_info->{end} ),
                    $target_info->{strand},
                    'No int primers',
                ), "\n";
            }
        }
        else {
            print $primer_fh join("\t",
                $target_info->{chr},
                join("-", $target_info->{start},
                     $target_info->{end} ),
                $target_info->{strand},
                'No ext primers',
            ), "\n";
        }
    }
}

=method print_nested_primers_to_file_and_plates

  Usage       : $crispr_design->print_nested_primers_to_file_and_plates( \%targets, $primer_fh, $plate_fh );
  Purpose     : Prints primer info for nested primers to both a file and a plate file
  Returns     : None
  Parameters  : Target info (HashRef)
                File Handle
                File Handle
  Throws      : 
  Comments    : 

=cut

sub print_nested_primers_to_file_and_plates {
    my ( $self, $targets, $primer_fh, $plate_fh ) = @_;
    
    my $row = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',];
    my $col = [1..12];
    my ($coli, $rowi, $plate) = (0,0,1);
    
    foreach my $id (sort keys %$targets) {
        my $target_info = $targets->{ $id };
        if (defined $target_info->{ext_primers}) {
            if (defined $target_info->{int_primers}) {
                
                print $plate_fh join("\t",
                    $plate,
                    $row->[$rowi] . $col->[$coli],
                    $target_info->{ext_primers}->pair_name,
                    $target_info->{ext_primers}->left_primer->primer_name,
                    $target_info->{ext_primers}->left_primer->seq,
                ), "\n";
                ( $rowi, $coli, $plate ) = $self->_increment_rows_columns($rowi, $coli, $plate);
                print $plate_fh join("\t",
                    $plate,
                    $row->[$rowi] . $col->[$coli],
                    $target_info->{int_primers}->pair_name,
                    $target_info->{int_primers}->left_primer->primer_name,
                    $target_info->{int_primers}->left_primer->seq,
                ), "\n";
                ( $rowi, $coli, $plate ) = $self->_increment_rows_columns($rowi, $coli, $plate);
                print $plate_fh join("\t",
                    $plate,
                    $row->[$rowi] . $col->[$coli],
                    $target_info->{int_primers}->pair_name,
                    $target_info->{int_primers}->right_primer->primer_name,
                    $target_info->{int_primers}->right_primer->seq,
                ), "\n";
                ( $rowi, $coli, $plate ) = $self->_increment_rows_columns($rowi, $coli, $plate);
                print $plate_fh join("\t",
                    $plate,
                    $row->[$rowi] . $col->[$coli],
                    $target_info->{ext_primers}->pair_name,
                    $target_info->{ext_primers}->right_primer->primer_name,
                    $target_info->{ext_primers}->right_primer->seq,
                ), "\n";
                ( $rowi, $coli, $plate ) = $self->_increment_rows_columns($rowi, $coli, $plate);
                
                print $primer_fh join("\t",
                    $target_info->{chr},
                    join("-", $target_info->{start},
                         $target_info->{end} ),
                    $target_info->{strand},
                    $target_info->{ext_primers}->product_size,
                    $target_info->{int_primers}->product_size,
                    $target_info->{ext_round},
                    $target_info->{int_round},
                    $target_info->{ext_primers}->pair_name,
                    $target_info->{int_primers}->pair_name,
                    $target_info->{ext_primers}->left_primer->primer_name,
                    $target_info->{ext_primers}->left_primer->seq,
                    $target_info->{int_primers}->left_primer->primer_name,
                    $target_info->{int_primers}->left_primer->seq,
                    $target_info->{int_primers}->right_primer->primer_name,
                    $target_info->{int_primers}->right_primer->seq,
                    $target_info->{ext_primers}->right_primer->primer_name,
                    $target_info->{ext_primers}->right_primer->seq,
                    $target_info->{ext_primers}->left_primer->length,
                    $target_info->{ext_primers}->left_primer->tm,
                    $target_info->{int_primers}->left_primer->length,
                    $target_info->{int_primers}->left_primer->tm,
                    $target_info->{int_primers}->right_primer->length,
                    $target_info->{int_primers}->right_primer->tm,
                    $target_info->{ext_primers}->right_primer->length,
                    $target_info->{ext_primers}->right_primer->tm,
                ), "\n";
            }
            else {
                foreach ( 1..4 ){
                    print $plate_fh join("\t",
                        $plate,
                        $row->[$rowi] . $col->[$coli],
                        'EMPTY',
                        'EMPTY',
                        'EMPTY',
                    ), "\n";
                    ( $rowi, $coli, $plate ) = $self->_increment_rows_columns($rowi, $coli, $plate);
                }
                print $primer_fh join("\t",
                    $target_info->{chr},
                    join("-", $target_info->{start},
                         $target_info->{end} ),
                    $target_info->{strand},
                    'No int primers',
                ), "\n";
            }
        }
        else {
            foreach ( 1..4 ){
                print $plate_fh join("\t",
                    $plate,
                    $row->[$rowi] . $col->[$coli],
                    'EMPTY',
                    'EMPTY',
                    'EMPTY',
                ), "\n";
                ( $rowi, $coli, $plate ) = $self->_increment_rows_columns($rowi, $coli, $plate);
            }
            
            print $primer_fh join("\t",
                $target_info->{chr},
                join("-", $target_info->{start},
                     $target_info->{end} ),
                $target_info->{strand},
                'No ext primers',
            ), "\n";
        }
    }
}

=method print_hrm_primers_header

  Usage       : $crispr_design->print_hrm_primers_header;
  Purpose     : Returns a list of column names for High-Res melting primers
  Returns     : Array
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub print_hrm_primers_header {
    my ( $self, ) = @_;
    return join("\t",
    'id', 'chromosome', 'cut-site', 'strand',
    'hrm_amp_size',
    'hrm_round',
    'hrm_pair_name',
    'hrm_left_id', 'hrm_left_seq',
    'hrm_right_id', 'hrm_right_seq',
    'length1', 'tm1',
    'length2', 'tm2',
    'variants_in_product_all', 'variants_in_product_founder',
    ), "\n";
}

=method print_hrm_primers_to_file

  Usage       : $crispr_design->print_hrm_primers_to_file( \%targets, $primer_fh, $plate_fh, $rowi, $coli, $plate );
  Purpose     : Prints info about HRM primers to a file handle
  Returns     : 
  Parameters  : 
  Throws      : 
  Comments    : 

=cut

sub print_hrm_primers_to_file {
    my ( $self, $targets, $primer_fh, $plate_fh, $rowi, $coli, $plate ) = @_;
    
    my $row = ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H',];
    my $col = [1..12];
    $rowi = $rowi   ?   $rowi   :   0;   
    $coli = $coli   ?   $coli   :   0;
    $plate = $plate   ?   $plate   :   1;   
    
    foreach my $id (sort keys %$targets) {
        my $target_info = $targets->{$id};
        if (defined $target_info->{hrm_primers}) {
            my $primer_pair = $target_info->{hrm_primers};
            $target_info->{primers_designed} = 1;
            next if( $primer_pair->type ne 'hrm' );
            if( $primer_pair->primer_pair_id ){
                $primer_pair->pair_id( $primer_pair->primer_pair_id );
            }
            else{
                $primer_pair->pair_id(
                    join(":", $target_info->{chr},
                                $target_info->{hrm_cut_site},
                                $target_info->{strand},
                                $target_info->{hrm_round}, )
                    );
            }
            #if ($target_info->{strand} > 0) {
            #    my $pcr_product_start = $target_info->{hrm_start} + $primer_pair->left_primer->index_pos;
            #    $primer_pair->left_primer_name(
            #        join(":",
            #            $target_info->{chr},
            #            join("-", $pcr_product_start,
            #            $pcr_product_start + ( $primer_pair->left_primer->length - 1 ), ),
            #            '1',
            #        )
            #    );
            #    $primer_pair->right_primer_name(
            #        join(":",
            #            $target_info->{chr},
            #            join("-",  ( $pcr_product_start +
            #            ( $primer_pair->product_size - 1 ) -
            #            ( $primer_pair->right_primer->length - 1) ),
            #            $pcr_product_start + ( $primer_pair->product_size - 1 ), ),
            #            '-1',
            #        )
            #    );
            #}
            #else {
            #    my $pcr_product_end = $target_info->{hrm_end} - $primer_pair->left_primer->index_pos;
            #    $primer_pair->left_primer_name(
            #        join(":",
            #            $target_info->{chr},
            #            join("-", $pcr_product_end -
            #                       ($primer_pair->left_primer->length - 1),
            #            $pcr_product_end ),
            #            '-1',
            #        )
            #    );
            #    $primer_pair->right_primer_name(
            #        join(":",
            #            $target_info->{chr},
            #            join("-", $pcr_product_end - ( $primer_pair->product_size - 1 ),
            #                $pcr_product_end - ( $primer_pair->product_size - 1 ) +
            #                    ( $primer_pair->right_primer->length - 1 ), ),
            #            '1',
            #        )
            #    );
            #}
            print $plate_fh join("\t",
                                $plate,
                                $row->[$rowi] . $col->[$coli],
                                $target_info->{target}->name,
                                $primer_pair->left_primer->primer_name,
                                $primer_pair->left_primer->seq,
                            ), "\n";
            ( $rowi, $coli, $plate ) = $self->_increment_rows_columns($rowi, $coli, $plate);
            print $plate_fh join("\t",
                                $plate,
                                $row->[$rowi] . $col->[$coli],
                                $target_info->{target}->name,
                                $primer_pair->right_primer->primer_name,
                                $primer_pair->right_primer->seq,
                            ), "\n";
            ( $rowi, $coli, $plate ) = $self->_increment_rows_columns($rowi, $coli, $plate);
            
            print $primer_fh join("\t",
                $targets->{$id}->{target}->name,
                $target_info->{chr},
                $target_info->{hrm_cut_site},
                $target_info->{strand},
                $primer_pair->product_size,
                $target_info->{hrm_round},
                $primer_pair->pair_id,
                $primer_pair->left_primer->primer_name,
                $primer_pair->left_primer->seq,
                $primer_pair->right_primer->primer_name,
                $primer_pair->right_primer->seq,
                $primer_pair->left_primer->length,
                $primer_pair->left_primer->tm,
                $primer_pair->right_primer->length,
                $primer_pair->right_primer->tm,
                $primer_pair->variants_in_pcr_product_all,
                $primer_pair->variants_in_pcr_product_founder,
            ), "\n";
        }
        else {
            print $plate_fh join("\t",
                                $plate,
                                $row->[$rowi] . $col->[$coli],
                                'EMPTY',
                                'EMPTY',
                                'EMPTY',
                            ), "\n";
            ( $rowi, $coli, $plate ) = $self->_increment_rows_columns($rowi, $coli, $plate);
            print $plate_fh join("\t",
                                $plate,
                                $row->[$rowi] . $col->[$coli],
                                'EMPTY',
                                'EMPTY',
                                'EMPTY',
                            ), "\n";
            ( $rowi, $coli, $plate ) = $self->_increment_rows_columns($rowi, $coli, $plate);
            
            print $primer_fh join("\t",
                $target_info->{chr},
                $target_info->{hrm_cut_site},
                $target_info->{strand},
                'No hrm primers',
            ), "\n";
        }
    }
    return ( $rowi, $coli, $plate );
}

=method _increment_rows_columns

  Usage       : $crispr_design->_increment_rows_columns;
  Purpose     : Internal method to increment row and column indices
  Returns     : 
  Parameters  : 
  Throws      : 
  Comments    : Needs replacing with using a Plate object

=cut

sub _increment_rows_columns {
    my ( $self, $rowi, $coli, $plate ) = @_;
    $rowi++;
    $coli++ if $rowi > 7;
    $rowi = 0 if $rowi > 7;
    $plate++ if $coli > 12;
    $coli = 1 if $coli > 12;
    return ( $rowi, $coli, $plate );
}

=method print_nested_primers_to_file_and_mixed_plates

  Usage       : $crispr_design->print_nested_primers_to_file_and_mixed_plates( \%targets, $platei, $primer_fh, $plate_fh );
  Purpose     : Prints info about nested primers to a file and a plate file for ordering mixed plates
  Returns     : 
  Parameters  : 
  Throws      : 
  Comments    : 

=cut

sub print_nested_primers_to_file_and_mixed_plates {
	my ( $self, $targets, $platei, $primer_fh, $plate_fh ) = @_;
	
    # print primer details
    foreach my $target_info ( @{$targets} ){
        if (defined $target_info->{ext_primers}) {
            if (defined $target_info->{int_primers}) {
                
                print $primer_fh join("\t",
                    $target_info->{chr},
                    join("-", $target_info->{start},
                         $target_info->{end} ),
                    $target_info->{strand},
                    $target_info->{ext_primers}->product_size,
                    $target_info->{int_primers}->product_size,
                    $target_info->{ext_round},
                    $target_info->{int_round},
                    $target_info->{ext_primers}->pair_name,
                    $target_info->{int_primers}->pair_name,
                    $target_info->{ext_primers}->left_primer->primer_name,
                    $target_info->{ext_primers}->left_primer->seq,
                    $target_info->{int_primers}->left_primer->primer_name,
                    $target_info->{int_primers}->left_primer->seq,
                    $target_info->{int_primers}->right_primer->primer_name,
                    $target_info->{int_primers}->right_primer->seq,
                    $target_info->{ext_primers}->right_primer->primer_name,
                    $target_info->{ext_primers}->right_primer->seq,
                    $target_info->{ext_primers}->left_primer->length,
                    $target_info->{ext_primers}->left_primer->tm,
                    $target_info->{int_primers}->left_primer->length,
                    $target_info->{int_primers}->left_primer->tm,
                    $target_info->{int_primers}->right_primer->length,
                    $target_info->{int_primers}->right_primer->tm,
                    $target_info->{ext_primers}->right_primer->length,
                    $target_info->{ext_primers}->right_primer->tm,
                ), "\n";
            }
            else {
                print $primer_fh join("\t",
                    $target_info->{chr},
                    join("-", $target_info->{start},
                         $target_info->{end} ),
                    $target_info->{strand},
                    'No int primers',
                ), "\n";
            }
        }
        else {
            print $primer_fh join("\t",
                $target_info->{chr},
                join("-", $target_info->{start},
                     $target_info->{end} ),
                $target_info->{strand},
                'No ext primers',
            ), "\n";
        }
    }
    
	# initialise plate and wells
	my @row_for = qw( A B C D E F G H );
	my ( $rowi, $column ) = ( 0, 1 );
    if( !$platei ){
        $platei = 1;
    }
	
	# print header row
	print {$plate_fh} join("\t", qw{ Plate_Num Well Sequence Notes } ), "\n";
	
    my %suffixes_for = (
        ext => 'd',
        int => 'e',
    );
	# print all primers
    foreach my $type ( qw{ ext int } ){
        my $plate_name = $platei . $suffixes_for{$type};
        foreach my $target_info ( @{$targets} ){
            if( defined $target_info->{ $type . '_primers'} ){
                print {$plate_fh} join("\t", $plate_name, join('', $row_for[$rowi], $column ),
                                       $target_info->{ $type . '_primers'}->left_primer->seq, $target_info->{name} .'_F' ), "\n";
            }
            ( $rowi, $column, $platei, ) = $self->_increment_rows_columns( $rowi, $column, $platei, );
        }
        ( $rowi, $column ) = ( 0, 1 );
        foreach my $target_info ( @{$targets} ){
            if( defined $target_info->{ $type . '_primers'} ){
                $plate_name = $platei . $suffixes_for{$type};
                print {$plate_fh} join("\t", $plate_name, join('', $row_for[$rowi], $column ),
                                       $target_info->{ $type . '_primers'}->right_primer->seq, $target_info->{name} .'_R' ), "\n";
            }
            ( $rowi, $column, $platei, ) = $self->_increment_rows_columns( $rowi, $column, $platei, );
        }
        ( $rowi, $column ) = ( 0, 1 );
    }
	
	return ++$platei;
}


1;
