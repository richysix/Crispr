## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::Plex;

## use critic

# ABSTRACT: Plex object - representing a multiplexed sequencing run

use warnings;
use strict;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use DateTime;

with 'Crispr::SharedMethods';

=method new

  Usage       : my $plex = Crispr::DB::Plex->new(
					db_id => undef,
                    plex_name => 'MPX14',
					run_id => 12345,
					analysis_started => '2014-09-27',
					analysis_finished => '2014-10-06',
                );
  Purpose     : Constructor for creating Plex objects
  Returns     : Crispr::DB::Plex object
  Parameters  : db_id => Int,
                plex_name => Str,
                run_id => Int,
                analysis_started => Date,
                analysis_finished => Date,
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method db_id

  Usage       : $plex->db_id;
  Purpose     : Getter/Setter for Plex db_id attribute
  Returns     : Int (can be undef)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'db_id' => (
    is => 'rw',
    isa => 'Maybe[Int]',
);

=method plex_name

  Usage       : $plex->plex_name;
  Purpose     : Getter for Plex plex_name attribute
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'plex_name' => (
    is => 'ro',
    isa => 'Str',
);

=method run_id

  Usage       : $plex->run_id;
  Purpose     : Getter for run_id attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'run_id' => (
    is => 'ro',
    isa => 'Int',
);

=method analysis_started

  Usage       : $plex->analysis_started;
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

  Usage       : $plex->analysis_finished;
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

# around plex_name to return lowercase
around 'plex_name' => sub {
    my ( $method, $self, $input ) = @_;
    if( $input ){
        return $self->$method( $input );
    }
    else{
        if( defined $self->$method ){
            return lc( $self->$method );
        }
        else{
            return $self->$method;
        }
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


__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 SYNOPSIS
 
    use Crispr::DB::Plex;
    my $plex = Crispr::DB::Plex->new(
        db_id => undef,
        plex_name => 'MPX14',
        run_id => 12345,
        analysis_started => '2014-09-27',
        analysis_finished => '2014-10-06',
    );    
    
=head1 DESCRIPTION
 
Objects of this class represent a multiplexed sequencing run.

=head1 DIAGNOSTICS


=head1 DEPENDENCIES
 
 Moose
 
=head1 INCOMPATIBILITIES
 

