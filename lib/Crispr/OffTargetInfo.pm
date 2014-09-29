## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::OffTargetInfo;
## use critic

# ABSTRACT: OffTargetInfo object - representing all possible off-target positions for a crispr guide RNA

use namespace::autoclean;
use Moose;
use Moose::Util::TypeConstraints;
use Carp qw( cluck confess );

use Number::Format;
my $num = new Number::Format( DECIMAL_DIGITS => 3, );

has '_off_targets' => (
    is => 'rw',
    isa => 'HashRef',
    lazy => 1,
    builder => '_build_off_targets',
    init_arg => undef,
);

sub add_off_target {
    my ( $self, $off_target, ) = @_;
    
    if( !ref $off_target || !$off_target->isa('Crispr::OffTarget') ){
        confess "Argument must be a Crispr::OffTarget object!\n";
    }
    push @{ $self->_off_targets->{ $off_target->annotation } }, $off_target;
}

sub all_off_targets {
    my ( $self, ) = @_;
    return ( @{ $self->_off_targets->{exon} }, @{ $self->_off_targets->{intron} }, @{ $self->_off_targets->{nongenic} }, );
}

sub score {
    my ( $self ) = @_;
    
    my $score = 1;
    if( $self->number_exon_hits ){
        $score -= 0.1*$self->number_exon_hits;
    }
    if( $self->number_intron_hits ){
        $score -= 0.05*$self->number_intron_hits;
    }
    if( $self->number_nongenic_hits ){
        $score -= 0.02*$self->number_nongenic_hits;
    }
    if( $score < 0 ){
        $score = 0;
    }
    elsif( $score > 1 ){
        confess "score is larger than 1!\n";
    }
    else{
        return $score;
    }
}

sub info {
    my ( $self, ) = @_;
	
    my @info;
    # off-target score
    push @info, $num->format_number($self->score);
    
	# scores and detail
    push @info, $self->off_target_counts;
    my @hits = $self->off_target_hits;
    push @info, join('|',
                    join('/', @{$hits[0]} ),
                    join('/', @{$hits[1]} ),
                    join('/', @{$hits[2]} ),
                );
    
    return @info;
}

sub off_target_counts {
    my ( $self, ) = @_;
    
    my @exo_hit_numbers = (
        $self->number_exon_hits,
        $self->number_intron_hits,
        $self->number_nongenic_hits,
    );
    return join('/', @exo_hit_numbers );
}

sub off_target_hits {
    my ( $self, ) = @_;
    
    my @exon_hits = map { $_->position } @{ $self->_off_targets->{ exon } };
    my @intron_hits = map { $_->position } @{ $self->_off_targets->{ intron } };
    my @nongenic_hits = map { $_->position } @{ $self->_off_targets->{ nongenic } };
    
    return ( \@exon_hits, \@intron_hits, \@nongenic_hits, )
}

sub number_exon_hits {
    my ( $self, ) = @_;
    return scalar @{$self->_off_targets->{exon}};
}

sub number_intron_hits {
    my ( $self, ) = @_;
    return scalar @{$self->_off_targets->{intron}};
}

sub number_nongenic_hits {
    my ( $self, ) = @_;
    return scalar @{$self->_off_targets->{nongenic}};
}

sub _build_off_targets {
    my ( $self, ) = @_;
    
    my $off_targets = {
        exon => [  ],
        intron => [  ],
        nongenic => [  ],
    };
    
    return $off_targets;
}

__PACKAGE__->meta->make_immutable;
1;
