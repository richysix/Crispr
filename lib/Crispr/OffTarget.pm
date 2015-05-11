## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::OffTarget;
## use critic

# ABSTRACT: OffTarget object - representing an off-target position for a crispr guide RNA

use namespace::autoclean;
use Moose;
use Moose::Util::TypeConstraints;

=method new

  Usage       : my $off_target = Crispr::OffTarget->new(
					crRNA_name => 'crRNA:5:101-123:1',
					chr => '7',
					start => 801,
					end => 823,
					strand => '-1',
					mismatches => 2,
					annotation => 'exon',
                );
  Purpose     : Constructor for creating crRNA objects
  Returns     : Crispr::OffTarget object
  Parameters  : crRNA_name  => Str
                chr         => Str
                start       => Int
                end         => Int
                strand      => Str ('1' OR '-1')
                mismatches  => 2,
                annotation  => Str
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method crRNA_name

  Usage       : $off_target->crRNA_name;
  Purpose     : Getter for crRNA_name
  Returns     : Str  (CHR:START-END:STRAND)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'crRNA_name' => (
    is => 'ro',
    isa => 'Str',
);

=method chr

  Usage       : $off_target->chr;
  Purpose     : Getter for chr
  Returns     : Str  (CHR:START-END:STRAND)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'chr' => (
    is => 'ro',
    isa => 'Str',
);

=method start

  Usage       : $off_target->start;
  Purpose     : Getter for start
  Returns     : Str  (CHR:START-END:STRAND)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method end

  Usage       : $off_target->end;
  Purpose     : Getter for end
  Returns     : Str  (CHR:START-END:STRAND)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has [ 'start', 'end' ] => (
    is => 'ro',
    isa => 'Int',
);

=method strand

  Usage       : $off_target->strand;
  Purpose     : Getter for strand
  Returns     : Str  (CHR:START-END:STRAND)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'strand' => (
    is => 'ro',
    isa => enum( [ qw{ 1 -1 } ] ),
    default => '1',
);

=method mismatches

  Usage       : $off_target->mismatches;
  Purpose     : Getter for mismatches
  Returns     : Str  (CHR:START-END:STRAND)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'mismatches' => (
    is => 'ro',
    isa => 'Int',
);

=method annotation

  Usage       : $off_target->annotation;
  Purpose     : Getter for annotation
  Returns     : Str  (CHR:START-END:STRAND)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'annotation' => (
    is => 'ro',
    isa => enum( [ qw{ exon intron nongenic } ] ),
);

=method position

  Usage       : $off_target->position;
  Purpose     : Getter for Position
  Returns     : Str  (CHR:START-END:STRAND)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub position {
    my ( $self, ) = @_;
    return $self->chr . ':' . $self->start . '-' . $self->end . ':' . $self->strand;
}

__PACKAGE__->meta->make_immutable;
1;
