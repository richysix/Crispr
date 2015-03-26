## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::Sample;
## use critic

# ABSTRACT: Sample object - representing a sample to be sequenced

use warnings;
use strict;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use DateTime;

with 'Crispr::SharedMethods';

=method new

  Usage       : my $sample = Crispr::DB::Sample->new(
					db_id => undef,
                    injection_pool => $inj_pool,
					subplex => $subplex,
					barcode_id => 1,
					generation => 'G0',
                    sample_type => 'sperm',
                    well_id => 'A01',
                );
  Purpose     : Constructor for creating Sample objects
  Returns     : Crispr::DB::Sample object
  Parameters  : db_id => Int,
                injection_pool => Crispr::DB::InjectionPool,
                subplex => Crispr::DB:Subplex,
                barcode_id => Int,
                generation => Str ('G0', 'F1', OR 'F2' ),
                sample_type => Str ( 'sperm', 'embryo', 'fin_clip' ),
                well_id => Str,
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method db_id

  Usage       : $inj->db_id;
  Purpose     : Getter/Setter for Sample db_id attribute
  Returns     : Int (can be undef)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'db_id' => (
    is => 'rw',
    isa => 'Maybe[Int]',
);

=method injection_pool

  Usage       : $inj->injection_pool;
  Purpose     : Getter for Sample injection_pool attribute
  Returns     : Crispr::DB::InjectionPool
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'injection_pool' => (
    is => 'ro',
    isa => 'Crispr::DB::InjectionPool',
);

=method subplex

  Usage       : $inj->subplex;
  Purpose     : Getter for subplex attribute
  Returns     : Crispr::DB::Subplex object
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'subplex' => (
    is => 'ro',
    isa => 'Crispr::DB::Subplex',
);

=method barcode_id

  Usage       : $inj->barcode_id;
  Purpose     : Getter for barcode_id attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'barcode_id' => (
    is => 'ro',
	isa =>  'Int',
);

=method generation

  Usage       : $inj->generation;
  Purpose     : Getter for generation attribute
  Returns     : Str ('G0', 'F1', OR 'F2' )
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'generation' => (
    is => 'ro',
    isa => enum( [ qw{ G0 F1 F2 } ] ),
);

=method sample_type

  Usage       : $target->sample_type;
  Purpose     : Getter for sample_type attribute
  Returns     : Str ('sperm', 'embryo' OR 'fin_clip')
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'sample_type' => (
    is => 'ro',
    isa => enum( [ qw{ sperm embryo fin_clip } ] ),
);

=method well_id

  Usage       : $target->well_id;
  Purpose     : Getter for well_id attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'well_id' => (
    is => 'ro',
    isa => 'Str',
);

=method alleles

  Usage       : $target->alleles;
  Purpose     : Getter/Setter for alleles attribute
  Returns     : ArrayRef[ Crispr::Allele ]
  Parameters  : ArrayRef[ Crispr::Allele ]
  Throws      : 
  Comments    : 

=cut

has 'alleles' => (
    is => 'rw',
    isa => 'Maybe[ArrayRef[ Crispr::Allele ]]',
);

=method species

  Usage       : $target->species;
  Purpose     : Getter for species attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'species' => (
    is => 'ro',
    isa => 'Str',
    default => 'zebrafish',
);

sub sample_name {
    my ( $self, ) = @_;
    return join("_", $self->subplex->db_id, $self->well_id, );
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 SYNOPSIS
 
    use Crispr::DB::Sample;
    my $inj = Crispr::DB::Sample->new(
        db_id => undef,
        injection_pool => $inj,
        subplex => $subplex,
        barcode_id => 1,
        generation => 'G0',
        sample_type => 'sperm',
        well_id => 'A01',
    );    
    
=head1 DESCRIPTION
 
Objects of this class represent a sample for screening by sequencing.

=head1 DIAGNOSTICS


=head1 DEPENDENCIES
 
 Moose
 
=head1 INCOMPATIBILITIES
 

