## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::Primer;
## use critic

# ABSTRACT: Primer object - representing a PCR primer

use namespace::autoclean;
use Moose;
use Moose::Util::TypeConstraints;

extends 'PCR::Primer';

=method new

  Usage       : my $primer = PCR::Primer->new(
                    primer_id => undef,
                    plate_id => 1,
                    well_id => 'A01',
                    sequence => 'ATGTACCAGGAGAGAAGCCGAGC',
                    primer_name => '5:12345797-12345819:-1',
                    seq_region => '5',
                    seq_region_strand => '-1',
                    seq_region_start => 12345797,
                    seq_region_end => 12345819,
                    index_pos => 819,
                    length => 23,
                    self_end => 2.00,
                    penalty => 0.035127,
                    self_any => 4.00,
                    end_stability => 5.0300,
                    tm => 57.965,
                    gc_percent => 56.522,
                );
  Purpose     : Constructor for creating Primer objects
  Returns     : Crispr::Primer object
  Parameters  : primer_id           => Int,
                plate_id            => Int,
                well_id             => Str,
                sequence            => Str
                primer_name         => Str
                seq_region          => Str
                seq_region_strand   => '1' OR '-1'
                seq_region_start    => Int
                seq_region_end      => Int
                index_pos           => Int
                length              => Int
                self_end            => Num
                penalty             => Num
                self_any            => Num
                end_stability       => Num
                tm                  => Num
                gc_percent          => Num
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method primer_id

  Usage       : $primer->primer_id;
  Purpose     : Getter/Setter for primer_id attribute
  Returns     : Str (must be a valid DNA string)
  Parameters  : None
  Throws      : If input is given
  Comments    : Can be undef

=cut

has 'primer_id' => (
	is => 'rw',
	isa => 'Int',
);

=method plate_id

  Usage       : $primer->plate_id;
  Purpose     : Getter for plate_id attribute
  Returns     : Str (must be a valid DNA string)
  Parameters  : None
  Throws      : If input is given
  Comments    : Can be undef

=cut

has 'plate_id' => (
	is => 'ro',
	isa => 'Int',
);

=method well_id

  Usage       : $primer->well_id;
  Purpose     : Getter for well_id attribute
  Returns     : Str (must be a valid DNA string)
  Parameters  : None
  Throws      : If input is given
  Comments    : Can be undef

=cut

has 'well_id' => (
	is => 'ro',
	isa => 'Str',
);

=method sequence

  Usage       : $primer->sequence;
  Purpose     : Getter for sequence attribute
  Returns     : Str (must be a valid DNA string)
  Parameters  : None
  Throws      : If input is given
  Comments    : Can be undef

=cut

=method primer_name

  Usage       : $primer->primer_name;
  Purpose     : Getter for primer_name attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : Can be undef

=cut

=method seq_region

  Usage       : $primer->seq_region;
  Purpose     : Getter/Setter for seq_region (chromosome/scaffold) attribute
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : Can be undef

=cut

=method seq_region_strand

  Usage       : $primer->seq_region_strand;
  Purpose     : Getter/Setter for seq_region_strand attribute
  Returns     : Str (must be either a '1' OR '-1')
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method seq_region_start

  Usage       : $primer->seq_region_start;
  Purpose     : Getter/Setter for seq_region_start (start in genomic co-ordinates) attribute
  Returns     : Int
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method seq_region_end

  Usage       : $primer->seq_region_end;
  Purpose     : Getter for seq_region_end (end in genomic co-ordinates) attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method index_pos

  Usage       : $primer->index_pos;
  Purpose     : Getter/Setter for index_pos attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    : index_pos is the position on the supplied sequence at which the
                5 prime end of the primer starts

=cut

=method length

  Usage       : $primer->length;
  Purpose     : Getter for length attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method self_end

  Usage       : $primer->self_end;
  Purpose     : Getter for self_end attribute
  Returns     : Num
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method penalty

  Usage       : $primer->penalty;
  Purpose     : Getter for penalty attribute
  Returns     : Num
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method self_any

  Usage       : $primer->self_any;
  Purpose     : Getter for self_any attribute
  Returns     : Num
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method end_stability

  Usage       : $primer->end_stability;
  Purpose     : Getter for end_stability attribute
  Returns     : Num
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method tm

  Usage       : $primer->tm;
  Purpose     : Getter for tm attribute
  Returns     : Num
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method gc_percent

  Usage       : $primer->gc_percent;
  Purpose     : Getter for gc_percent attribute
  Returns     : Num
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method seq

  Usage       : $primer->seq;
  Purpose     : Getter for sequence attribute (synonym for sequence attribute)
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : !! sequence attribute is ro !!

=cut

=method primer_summary

  Usage       : $primer->primer_summary;
  Purpose     : Returns a summary about the primer
  Returns     : Array
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method primer_info

  Usage       : $primer->primer_info;
  Purpose     : Returns information about the primer
  Returns     : Array
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method primer_posn

  Usage       : $primer->primer_posn;
  Purpose     : Getter for primer_posn attribute
  Returns     : Str (CHR:START-END:STRAND)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

__PACKAGE__->meta->make_immutable;

1;

__END__

=pod

=head1 NAME
 
PCR::Primer - Object representing a PCR primer.

 
=head1 SYNOPSIS
 
    use Crispr::Primer;
    my $primer = Crispr::Primer->new(
        primer_id => undef,
        plate_id => 1,
        well_id => 'A01',
        sequence => 'ATGTACCAGGAGAGAAGCCGAGC',
        primer_name => '5:12345797-12345819:-1',
        seq_region => '5',
        seq_region_strand => '-1',
        seq_region_start => 12345797,
        seq_region_end => 12345819,
        index_pos => 819,
        length => 23,
        self_end => 2.00,
        penalty => 0.035127,
        self_any => 4.00,
        end_stability => 5.0300,
        tm => 57.965,
        gc_percent => 56.522,
    );
    
    # print out target summary or info
    print join("\t", $target->summary ), "\n";
    print join("\t", $target->info ), "\n";
    

=head1 DESCRIPTION
 
Objects of this class represent a single PCR primer. This is a subclass of the PCR::Primer object.
The Crispr specific attributes are those required for adding primer info to a MySQL database.
 
=head1 DEPENDENCIES
 
Moose

PCR::Primer
