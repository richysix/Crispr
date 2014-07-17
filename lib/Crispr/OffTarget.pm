## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::OffTarget;
## use critic

# ABSTRACT: OffTarget object - representing possible off-target positions for a crispr guide RNA

use namespace::autoclean;
use Moose;
use Moose::Util::TypeConstraints;
use Carp qw( cluck confess );

use Number::Format;
my $num = new Number::Format( DECIMAL_DIGITS => 3, );

has 'crRNA_name' => (
    is => 'ro',
    isa => 'Str',
);

has 'bwa_alignments' => (
    is => 'rw',
    isa => 'Maybe[ArrayRef[Str]]',
);

has 'bwa_exon_alignments' => (
    is => 'rw',
    isa => 'Maybe[ArrayRef[Str]]',
);

has 'number_bwa_intron_hits' => (
    is => 'rw',
    isa => 'Maybe[Num]',
);

has 'number_bwa_nongenic_hits' => (
    is => 'rw',
    isa => 'Maybe[Num]',
);

has 'seed_exon_alignments' => (
    is => 'rw',
    isa => 'Maybe[ArrayRef[Str]]',
);

has 'number_seed_intron_hits' => (
    is => 'rw',
    isa => 'Maybe[Num]',
);

has 'number_seed_nongenic_hits' => (
    is => 'rw',
    isa => 'Maybe[Num]',
);

has 'exonerate_exon_alignments' => (
    is => 'rw',
    isa => 'Maybe[ArrayRef[Str]]'
);

has 'number_exonerate_intron_hits' => (
    is => 'rw',
    isa => 'Maybe[Num]',
);

has 'number_exonerate_nongenic_hits' => (
    is => 'rw',
    isa => 'Maybe[Num]',
);

has 'off_target_method' => (
    is => 'ro',
    isa => enum( [ qw{ bwa exonerate } ] ),
    lazy => 1,
    default => 'bwa',
);

around 'seed_exon_alignments' => sub {
    my ( $method, $self, $input ) = @_;
    
    if( $input ){
        if( !ref $input ){
            my $mismatches = $self->$method();
            push @{$mismatches}, ( split /,/, $input );
            return $self->$method( $mismatches );
        }
        elsif( ref $input eq 'ARRAY' ){
            my $mismatches = $self->$method();
            push @{$mismatches}, @{$input};
            return $self->$method( $mismatches );
        }
        else{
            confess "Input must be either an ArrayRef or a scalar!\n";
        }
    }
    else{
        return $self->$method();
    }
};

around 'exonerate_exon_alignments' => sub {
    my ( $method, $self, $input ) = @_;
    
    if( $input ){
        if( !ref $input ){
            my $mismatches = $self->$method();
            push @{$mismatches}, ( split /,/, $input );
            return $self->$method( $mismatches );
        }
        elsif( ref $input eq 'ARRAY' ){
            my $mismatches = $self->$method();
            push @{$mismatches}, @{$input};
            return $self->$method( $mismatches );
        }
        else{
            confess "Input must be either an ArrayRef or a scalar!\n";
        }
    }
    else{
        return $self->$method();
    }
};

around 'bwa_alignments' => sub {
    my ( $method, $self, $input ) = @_;
    
    if( $input ){
        if( !ref $input ){
            my $alignments = $self->$method();
            push @{$alignments}, ( split /,/, $input );
            return $self->$method( $alignments );
        }
        elsif( ref $input eq 'ARRAY' ){
            my $alignments = $self->$method();
            push @{$alignments}, @{$input};
            return $self->$method( $alignments );
        }
        else{
            confess "Input must be either an ArrayRef or a scalar!\n";
        }
    }
    else{
        return $self->$method();
    }
};

around 'bwa_exon_alignments' => sub {
    my ( $method, $self, $input ) = @_;
    
    if( $input ){
        if( !ref $input ){
            my $alignments = $self->$method();
            push @{$alignments}, ( split /,/, $input );
            return $self->$method( $alignments );
        }
        elsif( ref $input eq 'ARRAY' ){
            my $alignments = $self->$method();
            push @{$alignments}, @{$input};
            return $self->$method( $alignments );
        }
        else{
            confess "Input must be either an ArrayRef or a scalar!\n";
        }
    }
    else{
        return $self->$method();
    }
};

sub info {
    my ( $self, ) = @_;
	
    my @info;
    # off-target score
    if( defined $self->score ){
        push @info, $num->format_number($self->score);
    }
    else{
        push @info, 'NULL';
    }
    
	# scores and detail
    if( $self->off_target_method eq 'exonerate' ){
        # seed and exonerate
        if( defined $self->seed_score ){
            push @info, $num->format_number($self->seed_score);
        }
        else{
            push @info, 'NULL';
        }
        push @info, $self->seed_hits;
        
        if( defined $self->exonerate_score ){
            push @info, $num->format_number($self->exonerate_score);
        }
        else{
            push @info, 'NULL';
        }
        push @info, $self->exonerate_hits;
    }
    else{
        # bwa
        if( defined $self->bwa_score ){
            push @info, $num->format_number($self->bwa_score);
        }
        else{
            push @info, 'NULL';
        }
        push @info, $self->bwa_hits;
        push @info, qw{ NULL NULL };
    }
    return @info;
}

sub seed_hits {
    my ( $self, ) = @_;
    
    my @seed_hit_numbers;
    if( defined $self->number_seed_exon_hits ){
        if( $self->number_seed_exon_hits ){
            push @seed_hit_numbers, join(',', @{$self->seed_exon_alignments});
        }
        elsif( $self->number_seed_exon_hits == 0 ){
            push @seed_hit_numbers, $self->number_seed_exon_hits;
        }
    }
    else{
        push @seed_hit_numbers, 'NULL';
    }
    if( defined $self->number_seed_intron_hits ){
        push @seed_hit_numbers, $self->number_seed_intron_hits ;
    }
    else{
        push @seed_hit_numbers, 'NULL';
    }
    if( defined $self->number_seed_nongenic_hits ){
        push @seed_hit_numbers, $self->number_seed_nongenic_hits ;
    }
    else{
        push @seed_hit_numbers, 'NULL';
    }
    return join('/', @seed_hit_numbers );
}

sub number_seed_exon_hits {
    my ( $self, ) = @_;
    if( defined $self->seed_exon_alignments ){
        return scalar @{$self->seed_exon_alignments};
    }
    else{
        return;
    }
}

sub increment_seed_intron_hits {
    my ( $self, ) = @_;
    $self->number_seed_intron_hits( 0 ) if !defined $self->number_seed_intron_hits;
    $self->number_seed_intron_hits( $self->number_seed_intron_hits + 1 );
}

sub increment_seed_nongenic_hits {
    my ( $self, ) = @_;
    $self->number_seed_nongenic_hits( 0 ) if !defined $self->number_seed_nongenic_hits;
    $self->number_seed_nongenic_hits( $self->number_seed_nongenic_hits + 1 );
}

sub seed_score {
    my ( $self, ) = @_;
    if( !defined $self->number_seed_exon_hits &&
        !defined $self->number_seed_intron_hits &&
        !defined $self->number_seed_nongenic_hits ){
        return;
    }    
    my $score = 1;
    if( $self->number_seed_exon_hits ){
        $score *= 0.8**$self->number_seed_exon_hits;
    }
    if( $self->number_seed_intron_hits ){
        $score *= 0.9**$self->number_seed_intron_hits;
    }
    if( $self->number_seed_nongenic_hits ){
        $score *= 0.95**$self->number_seed_nongenic_hits;
    }
    if( $score < 0 || $score > 1 ){
        die "seed score is not between 0 and 1!\n";
    }
    else{
        return $score;
    }
}

sub exonerate_hits {
    my ( $self, ) = @_;
    
    my @exo_hit_numbers;
    if( defined $self->number_exonerate_exon_hits ){
        if( $self->number_exonerate_exon_hits ){
            push @exo_hit_numbers, join(',', @{$self->exonerate_exon_alignments});
        }
        elsif( $self->number_exonerate_exon_hits == 0 ){
            push @exo_hit_numbers, $self->number_exonerate_exon_hits;
        }
    }
    else{
        push @exo_hit_numbers, 'NULL';
    }
    if( defined $self->number_exonerate_intron_hits ){
        push @exo_hit_numbers, $self->number_exonerate_intron_hits ;
    }
    else{
        push @exo_hit_numbers, 'NULL';
    }
    if( defined $self->number_exonerate_nongenic_hits ){
        push @exo_hit_numbers, $self->number_exonerate_nongenic_hits ;
    }
    else{
        push @exo_hit_numbers, 'NULL';
    }
    return join('/', @exo_hit_numbers );
}

sub number_exonerate_exon_hits {
    my ( $self, ) = @_;
    if( defined $self->exonerate_exon_alignments ){
        return scalar @{$self->exonerate_exon_alignments};
    }
    else{
        return;
    }
}

sub increment_exonerate_intron_hits {
    my ( $self, ) = @_;
    $self->number_exonerate_intron_hits( 0 ) if !defined $self->number_exonerate_intron_hits;
    $self->number_exonerate_intron_hits( $self->number_exonerate_intron_hits + 1 );
}

sub increment_exonerate_nongenic_hits {
    my ( $self, ) = @_;
    $self->number_exonerate_nongenic_hits( 0 ) if !defined $self->number_exonerate_nongenic_hits;
    $self->number_exonerate_nongenic_hits( $self->number_exonerate_nongenic_hits + 1 );
}   

sub exonerate_score {
    my ( $self ) = @_;
    if( !defined $self->number_exonerate_exon_hits &&
        !defined $self->number_exonerate_intron_hits &&
        !defined $self->number_exonerate_nongenic_hits ){
        return;
    }    
    my $score = 1;
    if( $self->number_exonerate_exon_hits ){
        $score *= 0.8**$self->number_exonerate_exon_hits;
    }
    if( $self->number_exonerate_intron_hits ){
        $score *= 0.9**$self->number_exonerate_intron_hits;
    }
    if( $self->number_exonerate_nongenic_hits ){
        $score *= 0.95**$self->number_exonerate_nongenic_hits;
    }
    if( $score < 0 || $score > 1 ){
        die "exonerate score is not between 0 and 1!\n";
    }
    else{
        return $score;
    }
}

sub bwa_hits {
    my ( $self, ) = @_;
    
    my @exo_hit_numbers;
    if( defined $self->number_bwa_exon_hits ){
        if( $self->number_bwa_exon_hits ){
            push @exo_hit_numbers, join(',', @{$self->bwa_exon_alignments});
        }
        elsif( $self->number_bwa_exon_hits == 0 ){
            push @exo_hit_numbers, $self->number_bwa_exon_hits;
        }
    }
    else{
        push @exo_hit_numbers, 'NULL';
    }
    if( defined $self->number_bwa_intron_hits ){
        push @exo_hit_numbers, $self->number_bwa_intron_hits ;
    }
    else{
        push @exo_hit_numbers, 'NULL';
    }
    if( defined $self->number_bwa_nongenic_hits ){
        push @exo_hit_numbers, $self->number_bwa_nongenic_hits ;
    }
    else{
        push @exo_hit_numbers, 'NULL';
    }
    return join('/', @exo_hit_numbers );
}

sub number_bwa_exon_hits {
    my ( $self, ) = @_;
    if( defined $self->bwa_exon_alignments ){
        return scalar @{$self->bwa_exon_alignments};
    }
    else{
        return;
    }
}

sub increment_bwa_intron_hits {
    my ( $self, ) = @_;
    $self->number_bwa_intron_hits( 0 ) if !defined $self->number_bwa_intron_hits;
    $self->number_bwa_intron_hits( $self->number_bwa_intron_hits + 1 );
}

sub increment_bwa_nongenic_hits {
    my ( $self, ) = @_;
    $self->number_bwa_nongenic_hits( 0 ) if !defined $self->number_bwa_nongenic_hits;
    $self->number_bwa_nongenic_hits( $self->number_bwa_nongenic_hits + 1 );
}   

sub bwa_score {
    my ( $self ) = @_;
    if( !defined $self->number_bwa_exon_hits &&
        !defined $self->number_bwa_intron_hits &&
        !defined $self->number_bwa_nongenic_hits ){
        return;
    }    
    my $score = 1;
    if( $self->number_bwa_exon_hits ){
        $score -= 0.1*$self->number_bwa_exon_hits;
    }
    if( $self->number_bwa_intron_hits ){
        $score -= 0.05*$self->number_bwa_intron_hits;
    }
    if( $self->number_bwa_nongenic_hits ){
        $score -= 0.02*$self->number_bwa_nongenic_hits;
    }
    if( $score < 0 ){
        $score = 0;
    }
    elsif( $score > 1 ){
        die "bwa score is larger than 1!\n";
    }
    else{
        return $score;
    }
}

sub score {
    my ( $self, ) = @_;
    
    my $score;
    if( $self->off_target_method eq 'exonerate' ){
        $score = $self->seed_score && $self->exonerate_score     ?   $self->seed_score * $self->exonerate_score
            :       $self->seed_score                               ?   $self->seed_score
            :       $self->exonerate_score                          ?   $self->exonerate_score
            :                                                           undef
            ;
    }
    elsif( $self->off_target_method eq 'bwa' ){
        $score = $self->bwa_score;
    }
    if( $score < 0 || $score > 1 ){
        die "overall score is not between 0 and 1!\n";
    }
    
    return $score;
}

__PACKAGE__->meta->make_immutable;
1;
