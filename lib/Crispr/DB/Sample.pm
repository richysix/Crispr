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
use Labware::Well;

with 'Crispr::SharedMethods';

=method new

  Usage       : my $sample = Crispr::DB::Sample->new(
					db_id => undef,
                    injection_pool => $inj_pool,
					generation => 'G0',
                    sample_type => 'sperm',
                    sample_name => '170_1'
                    sample_number => 12,
                    alleles => $alleles_array_ref,
                    total_reads => $total_reads,
                    species => 'zebrafish',
                    well => $well,
                    cryo_box => 'Cr_Sperm12'
                );
  Purpose     : Constructor for creating Sample objects
  Returns     : Crispr::DB::Sample object
  Parameters  : db_id => Int,
                injection_pool => Crispr::DB::InjectionPool,
                generation => Str ('G0', 'F1', OR 'F2' ),
                sample_type => Str ( 'sperm', 'embryo', 'fin_clip' ),
                sample_name => Str,
                sample_number => Int,
                alleles => ArrayRef[ Crispr::Allele ],
                total_reads => Int,
                species => Str
                well => Labware::Well,
                cryo_box => Str
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
    isa => enum( [ qw{ sperm embryo finclip earclip blastocyst } ] ),
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
    writer => '_set_alleles',
);

=method total_reads

  Usage       : $sample->total_reads;
  Purpose     : Getter/Setter for total_reads attribute
  Returns     : Int
  Parameters  : Int
  Throws      :
  Comments    :

=cut

has 'total_reads' => (
    is => 'rw',
    isa => 'Int',
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

=method well

  Usage       : $sample->well;
  Purpose     : Getter for well attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    :

=cut

has 'well' => (
    is => 'ro',
    isa => 'Maybe[Labware::Well]',
);

=method cryo_box

  Usage       : $sample->cryo_box;
  Purpose     : Getter for cryo_box attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    :

=cut

has 'cryo_box' => (
    is => 'ro',
    isa => 'Maybe[Str]',
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
    isa => 'Maybe[Str]',
    lazy => 1,
    builder => '_build_sample_name',
);

sub _build_sample_name {
    my ( $self, ) = @_;
    my $sample_name;
    if( defined $self->injection_pool ){
        if( defined $self->sample_number ){
            $sample_name = join("_", $self->injection_pool->pool_name, $self->sample_number, );
        }
        else{
            $sample_name = undef;
        }
    }
    else{
        $sample_name = undef;
    }
    return $sample_name;
}

=method add_allele

  Usage       : $allele->add_allele( $crRNA );
  Purpose     : add allele object to alleles attribute
  Returns     : 1 if successful
  Parameters  : None
  Throws      :
  Comments    :

=cut

sub add_allele {
    my ( $self, $allele ) = @_;
    my $current_alleles = $self->alleles;
    push @{$current_alleles}, $allele;
    $self->_set_alleles( $current_alleles );
    return 1;
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 SYNOPSIS

    use Crispr::DB::Sample;
    my $sample = Crispr::DB::Sample->new(
        db_id => undef,
        injection_pool => $inj_pool,
        generation => 'G0',
        sample_type => 'sperm',
        sample_name => '170_A01'
        sample_number => 12,
        alleles => $alleles_array_ref,
        species => 'zebrafish',
        well => $well,
        cryo_box => 'Cr_Sperm12'
    );

=head1 DESCRIPTION

Objects of this class represent a sample for screening by sequencing.

=head1 DIAGNOSTICS


=head1 DEPENDENCIES

 Moose

=head1 INCOMPATIBILITIES
