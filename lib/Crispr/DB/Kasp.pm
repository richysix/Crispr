## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::Kasp;
## use critic

# ABSTRACT: Sample object - representing a sample to be sequenced

use warnings;
use strict;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use DateTime;

=method new

  Usage       : my $inj = Crispr::DB::Kasp->new(
					assay_id => '555-1.656',
                    rack_id => 1,
					row_id => 4,
					col_id => 7,
                );
  Purpose     : Constructor for creating Sample objects
  Returns     : Crispr::DB::Kasp object
  Parameters  : assay_id => Str,
                rack_id => Int,
                row_id => Int,
                col_id => Int,
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method assay_id

  Usage       : $inj->assay_id;
  Purpose     : Getter/Setter for Sample assay_id attribute
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'assay_id' => (
    is => 'rw',
    isa => 'Str',
    required => 1,
);

=method allele

  Usage       : $inj->allele;
  Purpose     : Getter/Setter for Sample allele attribute
  Returns     : Crispr::DB:Allele object
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'allele' => (
    is => 'ro',
    isa => 'Crispr::DB::Allele',
);

=method rack_id

  Usage       : $inj->rack_id;
  Purpose     : Getter for Sample rack_id attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'rack_id' => (
    is => 'ro',
    isa => 'Int',
    required => 1,
);

=method row_id

  Usage       : $inj->row_id;
  Purpose     : Getter for row_id attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'row_id' => (
    is => 'ro',
    isa => 'Int',
    required => 1,
);

=method col_id

  Usage       : $inj->col_id;
  Purpose     : Getter for col_id attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
                If input is not a valid DNA sequence (ACGT)
  Comments    : 

=cut

has 'col_id' => (
    is => 'ro',
	isa =>  'Int',
    required => 1,
);


__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 SYNOPSIS
 
    use Crispr::DB::Kasp;
    my $inj = Crispr::DB::Kasp->new(
        assay_id => '555-1.656',
        rack_id => 1,
        row_id => 4,
        col_id => 7,
    );    
    
=head1 DESCRIPTION
 
Objects of this class represent a KASP assay for sample genotyping.

=head1 DIAGNOSTICS


=head1 DEPENDENCIES
 
 Moose
 
=head1 INCOMPATIBILITIES
 

