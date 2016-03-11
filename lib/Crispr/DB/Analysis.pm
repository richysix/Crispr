## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::Analysis;

## use critic

# ABSTRACT: Analysis object - representing a subset of samples on a multiplexed sequencing run

use warnings;
use strict;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use DateTime;

with 'Crispr::SharedMethods';

=method new

  Usage       : my $analysis = Crispr::DB::Analysis->new(
                    db_id => undef,
                    plex => $plex,
                    analysis_started => '2015-02-24',
                    analysis_finished => '2015-02-28',
                    info => \@sample_amplicon_pairs,
                );    
  Purpose     : Constructor for creating Analysis objects
  Returns     : Crispr::DB::Analysis object
  Parameters  : db_id => Int,
                info => ArrayRef of Crispr::DB:SampleAmplicons objects,
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method db_id

  Usage       : $analysis->db_id;
  Purpose     : Getter/Setter for Analysis db_id attribute
  Returns     : Int (can be undef)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'db_id' => (
    is => 'rw',
    isa => 'Maybe[Int]',
);

=method plex

  Usage       : $analysis->plex;
  Purpose     : Getter for Analysis plex attribute
  Returns     : Crispr::DB::Plex
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'plex' => (
    is => 'ro',
    isa => 'Crispr::DB::Plex',
);

=method analysis_started

  Usage       : $analysis->analysis_started;
  Purpose     : Getter for analysis_started attribute
  Returns     : DateTime
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'analysis_started' => (
    is => 'ro',
    isa => 'Maybe[DateTime]',
);

=method analysis_finished

  Usage       : $analysis->analysis_finished;
  Purpose     : Getter for analysis_finished attribute
  Returns     : DateTime
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'analysis_finished' => (
    is => 'ro',
    isa => 'Maybe[DateTime]',
);

=method info

  Usage       : $analysis->info;
  Purpose     : Getter for Analysis info attribute
  Returns     : ArrayRef of Crispr::DB::SampleAmplicons objects
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'info' => (
    is => 'ro',
    isa => 'ArrayRef[ Crispr::DB::SampleAmplicon ]',
);

around BUILDARGS => sub{
    my $method = shift;
    my $self = shift;
    my %args;
	
    if( !ref $_[0] ){
		for( my $i = 0; $i < scalar @_; $i += 2 ){
			my $k = $_[$i];
			my $v = $_[$i+1];
            if( $k eq 'analysis_started' ){
                if( defined $v && ( !ref $v || ref $v ne 'DateTime' ) ){
                    my $date_obj = $self->_parse_date( $v );
                    $v = $date_obj;
                }
            }
            if( $k eq 'analysis_finished' ){
                if( defined $v && ( !ref $v || ref $v ne 'DateTime' ) ){
                    my $date_obj = $self->_parse_date( $v );
                    $v = $date_obj;
                }
            }
			$args{ $k } = $v;
		}
	    return $self->$method( \%args );
	}
    elsif( ref $_[0] eq 'HASH' ){
        if( exists $_[0]->{'analysis_started'} ){
            if( defined $_[0]->{'analysis_started'} &&
                ( !ref $_[0]->{'analysis_started'} || ref $_[0]->{'analysis_started'} ne 'DateTime' ) ){
                my $date_obj = $self->_parse_date( $_[0]->{'analysis_started'} );
                $_[0]->{'analysis_started'} = $date_obj;
            }
        }
        if( exists $_[0]->{'analysis_finished'} ){
            if( defined $_[0]->{'analysis_finished'} &&
                ( !ref $_[0]->{'analysis_finished'} || ref $_[0]->{'analysis_finished'} ne 'DateTime' ) ){
                my $date_obj = $self->_parse_date( $_[0]->{'analysis_finished'} );
                $_[0]->{'analysis_finished'} = $date_obj;
            }
        }
        return $self->$method( $_[0] );
    }
    else{
        confess "method new called without Hash or Hashref.\n";
    }	
};

# around analysis_started and analysis_finished
# This is to accept either a DateTime object or a string in form yyyy-mm-dd
#   and also to return a string instead of the DateTime object
around [ qw{ analysis_started analysis_finished } ] => sub {
    my ( $method, $self, $input ) = @_;
    my $date_obj;
    
    if( $input ){
        #is the input already a DateTime object
        if( ref $input eq 'DateTime' ){
            $date_obj = $input;
        }
        else{
            # parse date info
            $date_obj = $self->_parse_date( $input );
        }
        return $self->$method( $date_obj );
    }
    else{
        if( defined $self->$method ){
            return $self->$method->ymd;
        }
        else{
            return $self->$method;
        }
    }
};

=method samples

  Usage       : $analysis->samples;
  Purpose     : Returns all the samples in the analysis
  Returns     : Array of Crispr::DB::Sample objects
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub samples {
    my ( $self, ) = @_;
    return map { $_->sample } @{ $self->info };
}

=method amplicons

  Usage       : $analysis->amplicons;
  Purpose     : Returns all the amplicons in the analysis
  Returns     : Array of Crispr::PrimerPair objects
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub amplicons {
    my ( $self, ) = @_;
    my %primer_pairs = ();
    foreach my $amplicon ( map { @{$_->amplicons} } @{ $self->info } ){
        $primer_pairs{ $amplicon->pair_name } = $amplicon;
    }
    return values %primer_pairs;
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 SYNOPSIS
 
    use Crispr::DB::Analysis;
    my $analysis = Crispr::DB::Analysis->new(
        db_id => undef,
        info => \@sample_amplicon_pairs,
    );    
    
=head1 DESCRIPTION
 
Objects of this class represent the pairing of samples and amplicons for screening by sequencing.

=head1 DIAGNOSTICS


=head1 DEPENDENCIES
 
 Moose
 
=head1 INCOMPATIBILITIES
 

