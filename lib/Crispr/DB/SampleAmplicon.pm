## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::SampleAmplicon;
## use critic

# ABSTRACT: SampleAmplicon object - representing a pairing of a sample with amplicons for analysis

use warnings;
use strict;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use DateTime;

=method new

  Usage       : my $sample_amplicon = Crispr::DB::SampleAmplicon->new(
                    analysis_id => $analysis_id,
                    sample => $sample,
                    amplicons => \@primer_pairs,
                    barcode_id => $barcode_id,
                    plate_number => $plate_number,
                    well_id => $well_id,
                );    
  Purpose     : Constructor for creating SampleAmplicon objects
  Returns     : Crispr::DB::SampleAmplicon object
  Parameters  : analysis_id =>  Int
                sample =>       Crispr::DB::Sample object
                amplicon =>     Crispr::PrimerPair object
                barcode_id =>   Int
                plate_number => Int
                well_id =>      Str
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method analysis_id

  Usage       : $sample_amplicon->analysis_id;
  Purpose     : Getter/Setter for SampleAmplicon analysis_id attribute
  Returns     : Crispr::DB::Sample object
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'analysis_id' => (
    is => 'ro',
    isa => 'Int',
);

=method sample

  Usage       : $sample_amplicon->sample;
  Purpose     : Getter/Setter for SampleAmplicon sample attribute
  Returns     : Crispr::DB::Sample object
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'sample' => (
    is => 'ro',
    isa => 'Crispr::DB::Sample',
    handles => {
        sample_name => 'sample_name',
    },
);

=method amplicons

  Usage       : $sample_amplicon->amplicons;
  Purpose     : Getter/Setter for SampleAmplicon amplicons attribute
  Returns     : ArrayRef of Crispr::PrimerPair objects
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'amplicons' => (
    is => 'ro',
    isa => 'ArrayRef[ Crispr::PrimerPair ]',
);

=method barcode_id

  Usage       : $sample_amplicon->barcode_id;
  Purpose     : Getter/Setter for SampleAmplicon barcode_id attribute
  Returns     : Int
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'barcode_id' => (
    is => 'ro',
    isa => 'Int',
);

=method plate_number

  Usage       : $sample_amplicon->plate_number;
  Purpose     : Getter/Setter for SampleAmplicon plate_number attribute
  Returns     : Int
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'plate_number' => (
    is => 'ro',
    isa => 'Int',
);

=method well_id

  Usage       : $sample_amplicon->well_id;
  Purpose     : Getter/Setter for SampleAmplicon well_id attribute
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'well_id' => (
    is => 'ro',
    isa => 'Str',
);

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 SYNOPSIS
 
    use Crispr::DB::SampleAmplicon;
    my $sample_amplicon_pairs = Crispr::DB::SampleAmplicon->new(
        sample => $sample,
        amplicons => \@primer_pairs,
        barcode_id => $barcode_id,
        plate_number => $plate_number,
        well_id => $well_id,
    );    
    
=head1 DESCRIPTION
 
Objects of this class represent the pairing of samples and amplicons for screening by sequencing.

=head1 DIAGNOSTICS


=head1 DEPENDENCIES
 
 Moose
 
=head1 INCOMPATIBILITIES
 

