## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::SampleAllele;

## use critic

# ABSTRACT: SampleAllele object - representing an allele in a specific sample

use warnings;
use strict;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use DateTime;
use Labware::Well;

with 'Crispr::SharedMethods';

=method new

  Usage       : my $sample_allele = Crispr::DB::SampleAllele->new(
                    sample => $sample
                    allele => $allele,
					percent_of_reads => 10.2,
                );
  Purpose     : Constructor for creating SampleAllele objects
  Returns     : Crispr::DB::SampleAllele object
  Parameters  : alleles => ArrayRef of Crispr::Allele
                percent_of_reads => Num
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method sample

  Usage       : $sample->sample;
  Purpose     : Getter/Setter for SampleAllele sample attribute
  Returns     : Int (can be undef)
  Parameters  : None
  Throws      :
  Comments    :

=cut

has 'sample' => (
    is => 'ro',
    isa => 'Crispr::DB::Sample',
    weak_ref => 1,
);

=method allele

  Usage       : $sample->allele;
  Purpose     : Getter/Setter for SampleAllele allele attribute
  Returns     : Int (can be undef)
  Parameters  : None
  Throws      :
  Comments    :

=cut

has 'allele' => (
    is => 'ro',
    isa => 'Crispr::Allele',
);

=method percent_of_reads

  Usage       : $sample->percent_of_reads;
  Purpose     : Getter for SampleAllele percent_of_reads attribute
  Returns     : Crispr::DB::InjectionPool
  Parameters  : None
  Throws      :
  Comments    :

=cut

has 'percent_of_reads' => (
    is => 'ro',
    isa => 'Num',
);

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 SYNOPSIS

    use Crispr::DB::SampleAllele;
    my $sample_allele = Crispr::DB::SampleAllele->new(
        sample => $sample
        allele => $allele,
        percent_of_reads => 10.2,
    );

=head1 DESCRIPTION

Objects of this class represent a specific instance of an allele found
at a specific frequency in a single sample after screening by sequencing.

=head1 DIAGNOSTICS


=head1 DEPENDENCIES

 Moose

=head1 INCOMPATIBILITIES
