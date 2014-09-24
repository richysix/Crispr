## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::OffTarget;
## use critic

# ABSTRACT: OffTarget object - representing an off-target position for a crispr guide RNA

use namespace::autoclean;
use Moose;
use Moose::Util::TypeConstraints;

has 'crRNA_name' => (
    is => 'ro',
    isa => 'Str',
);

has 'chr' => (
    is => 'ro',
    isa => 'Str',
);

has [ 'start', 'end' ] => (
    is => 'ro',
    isa => 'Int',
);

has 'strand' => (
    is => 'ro',
    isa => enum( [ qw{ 1 -1 } ] ),
    default => '1',
);

has 'mismatches' => (
    is => 'ro',
    isa => 'Int',
);

has 'annotation' => (
    is => 'ro',
    isa => enum( [ qw{ exon intron nongenic } ] ),
);

sub position {
    my ( $self, ) = @_;
    return $self->chr . ':' . $self->start . '-' . $self->end . ':' . $self->strand;
}

__PACKAGE__->meta->make_immutable;
1;
