## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::CrisprPair;
## use critic

# ABSTRACT: CrisprPair object - a representation of a pair of crispr guide RNAs

## Author         : rw4
## Maintainer     : rw4
## Created        : 2013-08-15
## Last commit by : $Author$
## Last modified  : $Date$
## Revision       : $Revision$
## Repository URL : $HeadURL$

use warnings;
use strict;
use autodie qw(:all);
use Moose;
use namespace::autoclean;
use Crispr::crRNA;
use Crispr::Target;

use Number::Format;
my $num = new Number::Format( DECIMAL_DIGITS => 3, );

=method new

  Usage       : my $target = Crispr::CrisprPair->new(
                    pair_id => undef,
                    target_name => 'target_del',
                    target_1 => $target_1,
                    target_2 => $target_2,
                    crRNA_1 => $crRNA_1,
                    crRNA_2 => $crRNA_2,
                    paired_off_targets => 0,
                    overhang_top => 'ACGATAGACGATAGACGAGATGAGACTTTTATTG',
                    overhang_bottom => 'CAATAAAAGTCTCATCTCGTCTATCGTCTATCGT',
                );
  Purpose     : Constructor for creating target objects
  Returns     : Crispr::CrisprPair object
  Parameters  : pair_id => Int,
                target_name => String,
                target_1 => Crispr::Target,
                target_2 => Crispr::Target,
                crRNA_1 => Crispr::crRNA,
                crRNA_2 => Crispr::crRNA,
                paired_off_targets => Int,
                overhang_top => String,
                overhang_bottom => String,
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method pair_id

  Usage       : $target->pair_id;
  Purpose     : Getter for pair_id (database id) attribute
  Returns     : Int (can be undef)
  Parameters  : 
  Throws      : 
  Comments    : 

=cut

has 'pair_id' => (
    is => 'ro',
    isa => 'Maybe[Int]',
    writer => '_set_pair_id',
);

=method target_name

  Usage       : $target->target_name;
  Purpose     : Getter for target_name attribute
  Returns     : String
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'target_name' => (
    is => 'ro',
    isa => 'Str',
);

=method target_1

  Usage       : $target->target_1;
  Purpose     : Getter for target_1 attribute
  Returns     : Crispr::Target
  Parameters  : 
  Throws      : 
  Comments    : 

=cut

=method target_2

  Usage       : $target->target_2;
  Purpose     : Getter for target_2 attribute
  Returns     : Crispr::Target
  Parameters  : 
  Throws      : 
  Comments    : 

=cut

has [ 'target_1', 'target_2' ] => (
    is => 'ro',
    isa => 'Crispr::Target',
);

=method crRNA_1

  Usage       : $target->crRNA_1;
  Purpose     : Getter for crRNA_1 attribute
  Returns     : Int (can be undef)
  Parameters  : 
  Throws      : 
  Comments    : 

=cut

=method crRNA_2

  Usage       : $target->crRNA_2;
  Purpose     : Getter for crRNA_2 attribute
  Returns     : Int (can be undef)
  Parameters  : 
  Throws      : 
  Comments    : 

=cut

has [ 'crRNA_1', 'crRNA_2' ] => (
    is => 'ro',
    isa => 'Crispr::crRNA',
);

=method paired_off_targets

  Usage       : $target->paired_off_targets;
  Purpose     : Getter for paired_off_targets attribute
  Returns     : Int
  Parameters  : 
  Throws      : 
  Comments    : 

=cut

has 'paired_off_targets' => (
    is => 'ro',
    isa => 'Int',
    writer => '_set_paired_off_targets',
);

=method overhang_top

  Usage       : $target->overhang_top;
  Purpose     : Getter for overhang_top attribute
  Returns     : String
  Parameters  : 
  Throws      : 
  Comments    : 

=cut

=method overhang_bottom

  Usage       : $target->overhang_bottom;
  Purpose     : Getter for overhang_bottom attribute
  Returns     : String
  Parameters  : 
  Throws      : 
  Comments    : 

=cut

has [ 'overhang_top', 'overhang_bottom' ] => (
    is => 'rw',
    isa => 'Str',
);

=method crRNAs

  Usage       : $target->crRNAs;
  Purpose     : Getter for crRNAs attribute
  Returns     : ArrayRef of Crispr::crRNA objects
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub crRNAs {
    my ( $self, ) = @_;
    return [ $self->crRNA_1, $self->crRNA_2 ];
}

=method pair_name

  Usage       : $target->pair_name;
  Purpose     : Getter for pair_name attribute. Combination of crRNA names.
  Returns     : String
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub pair_name {
    my ( $self, ) = @_;
    return $self->crRNA_1->name . q{.} . $self->crRNA_2->name;
}

=method name

  Usage       : $target->name;
  Purpose     : Getter for name attribute. Combination of crRNA names.
  Returns     : String
  Parameters  : None
  Throws      : 
  Comments    : Synonym for pair_name

=cut

sub name {
    my ( $self, ) = @_;
    return $self->crRNA_1->name . q{.} . $self->crRNA_2->name;
}

=method combined_single_off_target_score

  Usage       : $target->combined_single_off_target_score;
  Purpose     : Getter for combined_single_off_target_score attribute
  Returns     : Num
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub combined_single_off_target_score {
    my ( $self, ) = @_;
    return $self->crRNA_1->off_target_score * $self->crRNA_2->off_target_score;
}

=method combined_distance_from_targets

  Usage       : $target->combined_distance_from_targets;
  Purpose     : Getter for combined_distance_from_targets attribute
  Returns     : Int
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub combined_distance_from_targets {
    my ( $self, ) = @_;
    my $a_distance = $self->target_1->end - $self->crRNA_1->cut_site;
	my $b_distance = $self->crRNA_2->cut_site - $self->target_2->start;
    return $a_distance + $b_distance;
}

=method deletion_size

  Usage       : $target->deletion_size;
  Purpose     : Getter for deletion_size attribute (distance between cut-sites)
  Returns     : Int
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub deletion_size {
    my ( $self, ) = @_;
    return abs($self->crRNA_2->cut_site - $self->crRNA_1->cut_site);
}

=method pair_info

  Usage       : $target->pair_info;
  Purpose     : Getter for pair_info attribute. 
  Returns     : Array
  Parameters  : None
  Throws      : 
  Comments    : Returns info on both targets which may be the same.

=cut

sub pair_info {
    my ( $self, ) = @_;
    
    my @info;
    push @info, $self->target_name;
    push @info, $self->name;
    push @info, $self->paired_off_targets;
    push @info, $num->format_number($self->combined_single_off_target_score);
    push @info, $self->deletion_size;
    push @info, $self->target_1->info;
    $info[1] =~ s/_[a-z]\z//xms;
    push @info, $self->crRNA_1->info;
    push @info, $self->target_2->info;
    $info[15] =~ s/_[a-z]\z//xms;
    push @info, $self->crRNA_2->info;
    push @info, $self->combined_distance_from_targets;
    
    return @info;
}

=method increment_paired_off_targets

  Usage       : $target->increment_paired_off_targets;
  Purpose     : Getter for increment_paired_off_targets attribute
  Returns     : Int
  Parameters  : Increment   String (amount to increment the number of off-targets by: defaults to 1.)
  Throws      : 
  Comments    : 

=cut

sub increment_paired_off_targets {
    my ( $self, $increment, ) = @_;
    if( !$increment ){
        $increment = 1;
    }
    $self->_set_paired_off_targets( $self->paired_off_targets + $increment );
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 NAME
 
<Crispr::CrisprPair> - <Module for Crispr::CrisprPair objects.>

 
=head1 SYNOPSIS
 
    use Crispr::CrisprPair;
    my $cr_pair = Crispr::CrisprPair->new(
        pair_id => undef,
        target_name => 'target_del',
        target_1 => $target_1,
        target_2 => $target_2,
        crRNA_1 => $crRNA_1,
        crRNA_2 => $crRNA_2,
        paired_off_targets => 0,
        overhang_top => 'ACGATAGACGATAGACGAGATGAGACTTTTATTG',
        overhang_bottom => 'CAATAAAAGTCTCATCTCGTCTATCGTCTATCGT',
    );
    
    # print out pair info
    print join("\t", $cr_pair->info ), "\n";
    

=head1 DESCRIPTION
 
Object of this class represent two crispr guide RNAs to be used as a pair.
crRNA 1 is always the first on the chromosome and should be on the reverse strand.
crRNA 2 should be on the forward strand.

 
=head1 DIAGNOSTICS
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
=head1 DEPENDENCIES
 
 
=head1 INCOMPATIBILITIES
 
