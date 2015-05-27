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

  Usage       : $sample->db_id;
  Purpose     : Getter/Setter for Sample db_id attribute
  Returns     : Int (can be undef)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'db_id' => (
    is => 'rw',
    isa => 'Maybe[Int]',
    default => undef,
);

=method injection_pool

  Usage       : $sample->injection_pool;
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

=method generation

  Usage       : $sample->generation;
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

  Usage       : $sample->sample_type;
  Purpose     : Getter for sample_type attribute
  Returns     : Str ('sperm', 'embryo' OR 'finclip')
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'sample_type' => (
    is => 'ro',
    isa => enum( [ qw{ sperm embryo finclip earclip } ] ),
);

=method sample_number

  Usage       : $sample->sample_number;
  Purpose     : Getter for sample_number attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'sample_number' => (
    is => 'ro',
    isa => 'Int',
);

=method alleles

  Usage       : $sample->alleles;
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

  Usage       : $sample->species;
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

=method sample_name

  Usage       : $sample->sample_name;
  Purpose     : Getter for sample_name attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'sample_name' => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    builder => '_build_sample_name',
);

sub _build_sample_name {
    my ( $self, ) = @_;
    return join("_", $self->injection_pool->pool_name, $self->sample_number, );
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 SYNOPSIS
 
    use Crispr::DB::Sample;
    my $sample = Crispr::DB::Sample->new(
        db_id => undef,
        injection_pool => $inj,
        generation => 'G0',
        sample_type => 'sperm',
    );    
    
=head1 DESCRIPTION
 
Objects of this class represent a sample for screening by sequencing.

=head1 DIAGNOSTICS


=head1 DEPENDENCIES
 
 Moose
 
=head1 INCOMPATIBILITIES
 

