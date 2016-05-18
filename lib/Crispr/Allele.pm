## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::Allele;

## use critic

# ABSTRACT: Allele object - representing a sequence variant

use warnings;
use strict;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;

subtype 'Crispr::Allele::DNA',
    as 'Str',
    where { my $ok = 1;
            $ok = 0 if $_ eq '';
            my @bases = split //, $_;
            foreach my $base ( @bases ){
                if( $base !~ m/[ACGT]/ ){
                    $ok = 0;
                }
            }
            return $ok;
    },
    message { "Not a valid DNA sequence.\n" };

=method new

  Usage       : my $allele = Crispr::Allele->new(
                    db_id => undef,
                    chr => 'Zv9_scaffold12',
                    pos => 25364,
                    ref_allele => 'GT',
                    alt_allele => 'GACAG',
                    crisprs => $crisprs,
                    allele_number => 'sa564',
                    kaspar_assay => $kasp_assay,
                );
  Purpose     : Constructor for creating Allele objects
  Returns     : Crispr::Allele object
  Parameters  : db_id => Int,
                chr => Str,
                pos => Int,
                ref_allele => Str,
                alt_allele => Str,
                crisprs => ArrayRef[ Crispr::crRNA ],
                allele_number => Str,
                kaspar_assay => $kasp_assay,
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method db_id

  Usage       : $allele->db_id;
  Purpose     : Getter/Setter for Allele db_id attribute
  Returns     : Int (can be undef)
  Parameters  : None
  Throws      :
  Comments    :

=cut

has 'db_id' => (
    is => 'rw',
    isa => 'Maybe[Int]',
);

=method crisprs

  Usage       : $allele->crisprs;
  Purpose     : Getter for Allele crisprs attribute
  Returns     : ArrayRef
  Parameters  : None
  Throws      : If input is given
  Comments    :

=cut

has 'crisprs' => (
    is => 'ro',
    isa => 'Maybe[ArrayRef[ Crispr::crRNA ]]',
    writer => '_set_crisprs',
);

=method chr

  Usage       : $allele->chr;
  Purpose     : Getter for Allele chr attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    :

=cut

has 'chr' => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

=method pos

  Usage       : $allele->pos;
  Purpose     : Getter for pos attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    :

=cut

has 'pos' => (
    is => 'ro',
    isa => 'Int',
    required => 1,
);

=method ref_allele

  Usage       : $allele->ref_allele;
  Purpose     : Getter for ref_allele attribute
  Returns     : Str (must be valid DNA sequence)
  Parameters  : None
  Throws      : If input is given
                If input is not a valid DNA sequence (ACGT)
  Comments    :

=cut

has 'ref_allele' => (
    is => 'ro',
    isa =>  'Crispr::Allele::DNA',
    required => 1,
);

=method alt_allele

  Usage       : $allele->alt_allele;
  Purpose     : Getter for alt_allele attribute
  Returns     : Str (must be valid DNA sequence)
  Parameters  : None
  Throws      : If input is given
                If input is not a valid DNA sequence (ACGT)
  Comments    :

=cut

has 'alt_allele' => (
    is => 'ro',
    isa =>  'Crispr::Allele::DNA',
    required => 1,
);

=method allele_number

  Usage       : $allele->allele_number;
  Purpose     : Getter for Allele allele_number attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    :

=cut

has 'allele_number' => (
    is => 'ro',
    isa => 'Maybe[Int]',
);

=method kaspar_assay

  Usage       : $allele->kaspar_assay;
  Purpose     : Getter for Allele kaspar_assay attribute
  Returns     : Crispr::Kasp object
  Parameters  : None
  Throws      : If input is given
  Comments    :

=cut

has 'kaspar_assay' => (
    is => 'rw',
    isa => 'Maybe[ Crispr::Kasp ]',
    handles => {
        kaspar_id => 'assay_id',
        kaspar_rack_id => 'rack_id',
        kaspar_row_id => 'row_id',
        kaspar_col_id => 'col_id',
    },
);

=method allele_name

  Usage       : $allele->allele_name;
  Purpose     : Getter for Allele name attribute
  Returns     : Str  (CHR:POS:REF:ALT)
  Parameters  : None
  Throws      :
  Comments    :

=cut

sub allele_name {
    my ( $self, ) = @_;
    return join(":", $self->chr, $self->pos, $self->ref_allele, $self->alt_allele, );
}

=method add_crispr

  Usage       : $allele->add_crispr( $crRNA );
  Purpose     : add crispr object to crisprs attribute
  Returns     : 1 if successful
  Parameters  : None
  Throws      :
  Comments    :

=cut

sub add_crispr {
    my ( $self, $crRNA ) = @_;
    my $current_crisprs = $self->crisprs;
    push @{$current_crisprs}, $crRNA;
    $self->_set_crisprs( $current_crisprs );
    return 1;
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 SYNOPSIS

    use Crispr::Allele;
    my $allele = Crispr::Allele->new(
        db_id => undef,
        chr => 'Zv9_scaffold12',
        pos => 25364,
        ref_allele => 'GT',
        alt_allele => 'GACAG',
        allele_number => 'sa564',
        crisprs => [ $crRNA1, $crRNA2 ],
        kaspar_assay => $kasp_assay,
    );

=head1 DESCRIPTION

Objects of this class represent a variant allele.

=head1 DIAGNOSTICS


=head1 DEPENDENCIES

 Moose

=head1 INCOMPATIBILITIES
