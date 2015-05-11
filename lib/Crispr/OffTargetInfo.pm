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

=method new

  Usage       : my $off_target_info = Crispr::OffTarget->new(
					crRNA_name => 'crRNA:5:101-123:1',
                );
  Purpose     : Constructor for creating crRNA objects
  Returns     : Crispr::OffTarget object
  Parameters  : crRNA_name  => Str
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method crRNA_name

  Usage       : $off_target_info->crRNA_name;
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

=method _off_targets

  Usage       : $off_target_info->_off_targets;
  Purpose     : Attribute to hold the off-targets objects
  Returns     : HashRef
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has '_off_targets' => (
    is => 'rw',
    isa => 'HashRef',
    lazy => 1,
    builder => '_build_off_targets',
    init_arg => undef,
);

=method add_off_target

  Usage       : $off_target_info->add_off_target( $off_target );
  Purpose     : adds a single Crispr::OffTarget object
  Returns     : 
  Parameters  : None
  Throws      : If argument is not a Crispr::OffTarget object
  Comments    : 

=cut

sub add_off_target {
    my ( $self, $off_target, ) = @_;
    
    if( !ref $off_target || !$off_target->isa('Crispr::OffTarget') ){
        confess "Argument must be a Crispr::OffTarget object!\n";
    }
    push @{ $self->_off_targets->{ $off_target->annotation } }, $off_target;
}

=method all_off_targets

  Usage       : $off_target_info->all_off_targets;
  Purpose     : Returns a List of Crispr::OffTarget objects
  Returns     : Array( Crispr::OffTarget objects )
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub all_off_targets {
    my ( $self, ) = @_;
    return ( @{ $self->_off_targets->{exon} }, @{ $self->_off_targets->{intron} }, @{ $self->_off_targets->{nongenic} }, );
}

=method _make_and_add_off_target

  Usage       : $off_target_info->_make_and_add_off_target;
  Purpose     : Creates a new Crispr::OffTarget object from the arguments and
                adds it to the _off_targets attribute
  Returns     : Crispr::OffTarget 
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub _make_and_add_off_target {
    my ( $self, $args, ) = @_;
    
    my $off_target_obj = Crispr::OffTarget->new(
        crRNA_name => $args->{crRNA_name},
        chr => $args->{chr},
        start => $args->{start},
        end => $args->{end},
        strand => $args->{strand},
        mismatches => $args->{mismatches},
        annotation => $args->{annotation},
    );
    
    $self->add_off_target( $off_target_obj );
}

=method score

  Usage       : $off_target_info->score;
  Purpose     : Calculates an off target score from the OffTarget objects
  Returns     : Float
  Parameters  : None
  Throws      : If score is larger than 1
  Comments    : 

=cut

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

=method info

  Usage       : $off_target_info->info;
  Purpose     : Returns information about the Off Targets
  Returns     : Array( Str )
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub info {
    my ( $self, ) = @_;
	
    my @info;
    # off-target score
    push @info, $num->format_number($self->score);
    
	# scores and detail
    push @info, $self->off_target_counts;
    my @hits = $self->off_target_hits_by_annotation;
    push @info, join('|',
                    join('/', @{$hits[0]} ),
                    join('/', @{$hits[1]} ),
                    join('/', @{$hits[2]} ),
                );
    
    return @info;
}

=method off_target_counts

  Usage       : $off_target_info->off_target_counts;
  Purpose     : Returns the number of exon/intron/nongenic hits
  Returns     : Str (Exon/Intron/Nongenic)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub off_target_counts {
    my ( $self, ) = @_;
    
    my @exo_hit_numbers = (
        $self->number_exon_hits,
        $self->number_intron_hits,
        $self->number_nongenic_hits,
    );
    return join('/', @exo_hit_numbers );
}

=method off_target_hits_by_annotation

  Usage       : $off_target_info->off_target_hits_by_annotation;
  Purpose     : Returns the OffTarget positions split by annotation type
  Returns     : Array( [Exon Hits], [Intron Hits], [Nongenic Hits] )
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub off_target_hits_by_annotation {
    my ( $self, ) = @_;
    
    my @exon_hits = map { $_->position } @{ $self->_off_targets->{ exon } };
    my @intron_hits = map { $_->position } @{ $self->_off_targets->{ intron } };
    my @nongenic_hits = map { $_->position } @{ $self->_off_targets->{ nongenic } };
    
    return ( \@exon_hits, \@intron_hits, \@nongenic_hits, );
}

=method all_off_target_hits

  Usage       : $off_target_info->all_off_target_hits;
  Purpose     : Returns a list of all the Off Target Hits (positions)
  Returns     : ArrayRef[ Str ]
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub all_off_target_hits {
    my ( $self, ) = @_;
    
    my @exon_hits = map { $_->position } @{ $self->_off_targets->{ exon } };
    my @intron_hits = map { $_->position } @{ $self->_off_targets->{ intron } };
    my @nongenic_hits = map { $_->position } @{ $self->_off_targets->{ nongenic } };
    
    return ( [ @exon_hits, @intron_hits, @nongenic_hits ] );
}

=method number_exon_hits

  Usage       : $off_target_info->number_exon_hits;
  Purpose     : Returns the number of exon hits
  Returns     : Int
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub number_exon_hits {
    my ( $self, ) = @_;
    return scalar @{$self->_off_targets->{exon}};
}

=method number_intron_hits

  Usage       : $off_target_info->number_intron_hits;
  Purpose     : Returns the number of intron hits
  Returns     : Int
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub number_intron_hits {
    my ( $self, ) = @_;
    return scalar @{$self->_off_targets->{intron}};
}

=method number_nongenic_hits

  Usage       : $off_target_info->number_nongenic_hits;
  Purpose     : Returns the number of nongenic hits
  Returns     : Int
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub number_nongenic_hits {
    my ( $self, ) = @_;
    return scalar @{$self->_off_targets->{nongenic}};
}

=method number_hits

  Usage       : $off_target_info->number_hits;
  Purpose     : Returns the total number of off-target hits
  Returns     : Int
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub number_hits {
    my ( $self, ) = @_;
    return $self->number_exon_hits + $self->number_intron_hits + $self->number_nongenic_hits;
}

=method _build_off_targets

  Usage       : $off_target_info->_build_off_targets;
  Purpose     : Internal method to build the _off_targets attribute
  Returns     : HashRef[ exon => ArrayRef, intron => ArrayRef, Nongenic => ArrayRef ]
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

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
