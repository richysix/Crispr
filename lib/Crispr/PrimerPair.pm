## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::PrimerPair;
## use critic

# ABSTRACT: PrimerPair object - representing a pair of PCR primers

use Crispr::Primer;
use namespace::autoclean;
use Moose;
use Moose::Util::TypeConstraints;

extends 'PCR::PrimerPair';

my %types = (
	ext => 1,
	int => 1,
    'ext-illumina' => 1,
    'int-illumina' => 1,
    'int-illumina_tailed' => 1,
	hrm => 1,
	flag => 1,
	flag_revcom => 1,
	ha => 1,
	ha_revcom => 1,
);
my $error_message = "PrimerPair:Type attribute must be one of " . join(q{, }, sort keys %types) . ".\n";

subtype 'Crispr::PrimerPair::Type',
	as 'Str',
	where {
		my $ok = 0;
		$ok = 1 if( exists $types{ lc($_) } );
	},
	message { return $error_message; };


=method new

  Usage       : my $primer_pair = PCR::PrimerPair->new(
                    primer_pair_id => 1,
                    left_primer => $left_primer
                    right_primer => $right_primer
                    pair_name => '5:12345152-12345819:1:1',
                    amplicon_name => 'crRNA:5:12345678-12345700:1',
                    target => '701,23',
                    explain => 'considered 37, unacceptable product size 26, ok 11',
                    product_size_range => '500-1000',
                    excluded_regions => [ '651,122', '1282,29', ]
                    product_size => '668',
                    left_primer => $left_primer,
                    right_primer => $right_primer,
                    type => 'ext',
                    pair_compl_end => '0.00',
                    pair_compl_any => '3.00',
                    pair_penalty => '0.1303'
                );
  Purpose     : Constructor for creating PrimerPair objects
  Returns     : PCR::PrimerPair object
  Parameters  : pair_name           => Str
                amplicon_name       => Str
                target              => Str
                explain             => Str
                product_size_range  => Str
                excluded_regions    => ArrayRef
                product_size        => Int
                left_primer         => PCR::Primer
                right_primer        => PCR::Primer
                type                => Str
                pair_compl_end      => Num
                pair_compl_any      => Num
                pair_penalty        => Num
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method primer_pair_id

  Usage       : $primer->primer_pair_id;
  Purpose     : Getter/Setter for primer_pair_id attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'primer_pair_id' => (
	is => 'rw',
	isa => 'Int',
);

=method type

  Usage       : $primer->type;
  Purpose     : Getter for type attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : Must be one of 	ext, int, illumina, illumina_tailed, hrm, flag, flag_revcom, ha, OR ha_revcom

=cut

has 'type' => (
	is => 'rw',
	isa => 'Crispr::PrimerPair::Type',
);

=method left_primer

  Usage       : $primer->left_primer;
  Purpose     : Getter for left_primer attribute
  Returns     : Crispr::Primer
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'left_primer' => (
	is => 'ro',
	isa => 'Crispr::Primer',
	handles => {
		left_primer_name => 'primer_name',
	}
);

=method right_primer

  Usage       : $primer->right_primer;
  Purpose     : Getter for right_primer attribute
  Returns     : Crispr::Primer
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'right_primer' => (
	is => 'ro',
	isa => 'Crispr::Primer',
	handles => {
		right_primer_name => 'primer_name',
	}
);

=method seq_region

  Usage       : $primer->seq_region;
  Purpose     : Getter for seq_region attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : Can be undef

=cut

sub seq_region {
    my ( $self, ) = @_;
    return $self->left_primer->seq_region;
}

=method seq_region_start

  Usage       : $primer->seq_region_start;
  Purpose     : Getter for seq_region_start attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : Can be undef

=cut

sub seq_region_start {
    my ( $self, ) = @_;
    return $self->left_primer->seq_region_start < $self->right_primer->seq_region_start
        ?   $self->left_primer->seq_region_start
        :   $self->right_primer->seq_region_start;
}

=method seq_region_end

  Usage       : $primer->seq_region_end;
  Purpose     : Getter for seq_region_end attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : Can be undef

=cut

sub seq_region_end {
    my ( $self, ) = @_;
    return $self->left_primer->seq_region_end > $self->right_primer->seq_region_end
        ?   $self->left_primer->seq_region_end
        :   $self->right_primer->seq_region_end;
}

=method seq_region_strand

  Usage       : $primer->seq_region_strand;
  Purpose     : Getter for seq_region_strand attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : Can be undef

=cut

sub seq_region_strand {
    my ( $self, ) = @_;
    return $self->left_primer->seq_region_strand;
}

=method pair_name

  Usage       : $primer->pair_name;
  Purpose     : Getter/Setter for pair_name attribute
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method amplicon_name

  Usage       : $primer->amplicon_name;
  Purpose     : Getter for amplicon_name attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : Can be undef

=cut

=method warnings

  Usage       : $primer->warnings;
  Purpose     : Getter for warnings attribute
  Returns     : Str (must be a valid DNA string)
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method target

  Usage       : $primer->target;
  Purpose     : Getter for target attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method explain

  Usage       : $primer->explain;
  Purpose     : Getter for explain attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method product_size_range

  Usage       : $primer->product_size_range;
  Purpose     : Getter for product_size_range attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method excluded_regions

  Usage       : $primer->excluded_regions;
  Purpose     : Getter for excluded_regions attribute
  Returns     : ArrayRef
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method product_size

  Usage       : $primer->product_size;
  Purpose     : Getter for product_size attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method query_slice_start

  Usage       : $primer->query_slice_start;
  Purpose     : Getter for query_slice_start attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method query_slice_end

  Usage       : $primer->query_slice_end;
  Purpose     : Getter for query_slice_end attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method type

  Usage       : $primer->type;
  Purpose     : Getter for type attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : Must be one of 	ext, int, illumina, illumina_tailed, hrm, flag, flag_revcom, ha, OR ha_revcom

=cut

=method pair_compl_end

  Usage       : $primer->pair_compl_end;
  Purpose     : Getter for pair_compl_end attribute
  Returns     : Num
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method pair_compl_any

  Usage       : $primer->pair_compl_any;
  Purpose     : Getter for pair_compl_any attribute
  Returns     : Num
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method pair_compl_penalty

  Usage       : $primer->pair_compl_penalty;
  Purpose     : Getter for pair_compl_penalty attribute
  Returns     : Num
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method primer_pair_summary

  Usage       : $primer->primer_pair_summary;
  Purpose     : Returns a summary about the primer pair
                Amplicon Name, Product Size, Left Primer Summary, Right Primer Summary
  Returns     : Array
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method primer_pair_info

  Usage       : $primer->primer_pair_info;
  Purpose     : Returns Information about the primer pair
                Amplicon Name, Pair Name, Type, Product Size,
                Left Primer Info, Right Primer Info
  Returns     : Array
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 NAME
 
Cripsr::PrimerPair - Object representing a PCR primer pair.
 
=head1 SYNOPSIS
 
    use Crispr::PrimerPair;
    my $primer_pair = Crispr::PrimerPair->new(
        primer_pair_id => 1,
        left_primer => $left_primer
        right_primer => $right_primer
        pair_name => '5:12345152-12345819:1:1',
        amplicon_name => 'crRNA:5:12345678-12345700:1',
        target => '701,23',
        explain => 'considered 37, unacceptable product size 26, ok 11',
        product_size_range => '500-1000',
        excluded_regions => [ '651,122', '1282,29', ]
        product_size => '668',
        left_primer => $left_primer,
        right_primer => $right_primer,
        type => 'ext',
        pair_compl_end => '0.00',
        pair_compl_any => '3.00',
        pair_penalty => '0.1303'
    );
    
  
=head1 DESCRIPTION
 
Objects of this class represent a primer pair.
The object contains the objects for the two primers that make up the pair as well
as other information about the pair.

=head1 DEPENDENCIES
 
Moose

PCR::Primer
