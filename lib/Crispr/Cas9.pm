## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::Cas9;
## use critic

# ABSTRACT: Cas9 object - representing the Cas9 endonuclease

use warnings;
use strict;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use Readonly;

subtype 'Crispr::Cas9::DNA',
    as 'Str',
    where { 
        m/\A [ACGTNRYSWMKBDHV]+ \z/xms;
    },
    message { "Not a valid DNA sequence.\n" };

=method new

  Usage       : my $cas9 = Crispr::Cas9->new(
					type => 'ZfnCas9n',
					species => 's_pyogenes',
					target_seq => 'NNNNNNNNNNNNNNNNNN',
					PAM => 'NGG',
                    vector => 'pCS2'
                    name => 'pCS2-ZfnCas9n',
                );
  Purpose     : Constructor for creating Cas9 objects
  Returns     : Crispr::Cas9 object
  Parameters  : type => Str
                species => Str
                target_seq => Str (Crispr::Cas9::DNA)
                PAM => Str (Crispr::Cas9::DNA)
                vector => Str
                name => Str
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method db_id

  Usage       : $cas9->db_id;
  Purpose     : Getter for Cas9 db_id attribute
  Returns     : Int (can be undef)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'db_id' => (
    is => 'rw',
    isa => 'Maybe[Int]',
);

=method type

  Usage       : $cas9->type;
  Purpose     : Getter for Cas9 type attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

Readonly my @TYPES = ( qw{ ZfnCas9n ZfnCas9-D10An } );
has 'type' => (
    is => 'ro',
    isa => enum( \@TYPES ),
    default => $TYPES[0],
);

=method species

  Usage       : $cas9->species;
  Purpose     : Getter for species attribute
  Returns     : String
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'species' => (
    is => 'ro',
    isa => 'Str',
    default => 's_pyogenes',
);

=method target_seq

  Usage       : $cas9->target_seq;
  Purpose     : Getter for associated target_seq
  Returns     : String (Default = NNNNNNNNNNNNNNNNNN)
  Parameters  : None
  Throws      : If input is given
                If input is not a DNA sequence
  Comments    : 

=cut

has 'target_seq' => (
    is => 'ro',
    isa => 'Crispr::Cas9::DNA',
    lazy => 1,
    builder => '_build_target_seq',
);

=method PAM

  Usage       : $cas9->PAM;
  Purpose     : Getter for PAM attribute
  Returns     : String  (Default = NGG)
  Parameters  : None
  Throws      : If input is given
                If input is not a DNA sequence
  Comments    : 

=cut

has 'PAM' => (
    is => 'ro',
    isa => 'Crispr::Cas9::DNA',
    lazy => 1,
    builder => '_build_PAM',
);

=method vector

  Usage       : $cas9->vector;
  Purpose     : Getter for vector attribute
  Returns     : String
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'vector' => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    builder => '_build_vector',
);

=method name

  Usage       : $cas9->name;
  Purpose     : Getter for name attribute
  Returns     : String
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'name' => (
    is => 'ro',
    isa => 'Str',
    lazy => 1,
    builder => '_build_name',
);

around BUILDARGS => sub{
    my $method = shift;
    my $self = shift;
    my %args;
	
    if( !ref $_[0] ){
		for( my $i = 0; $i < scalar @_; $i += 2 ){
			my $k = $_[$i];
			my $v = $_[$i+1];
			if( $k eq 'species' ){
				my $species = $self->_parse_species( $v );
				$v = $species;
			}
			$args{ $k } = $v;
		}
	    return $self->$method( \%args );
	}
    elsif( ref $_[0] eq 'HASH' ){
        if( exists $_[0]->{'species'} ){
            if( defined $_[0]->{'species'} ){
				my $species = $self->_parse_species( $_[0]->{'species'} );
                $_[0]->{'species'} = $species;
            }
        }
        return $self->$method( $_[0] );
    }
    else{
        confess "method new called without Hash or Hashref.\n";
    }	
};

#_parse_species
#
#Usage       : $cas9->_parse_species( 'Danio_rerio' );
#Purpose     : tries to force common names for species
#Returns     : String
#Parameters  : String
#Throws      : 
#Comments    :

sub _parse_species {
	# force common names for species
	my ( $self, $input, ) = @_;
    my $species;
    my %name_for = (
        'streptococcus_pyogenes' => 's_pyogenes',
        'streptococcus pyogenes' => 's_pyogenes',
        's_pyogenes' => 's_pyogenes',
        's.pyogenes' => 's_pyogenes',
    );
    
    if( !$input ){
        return;
    }
    else{
        if( exists $name_for{ lc( $input ) } ){
            return $name_for{ lc( $input ) };
        }
        else{
            return $input;
        }
    }
};

=method info

  Usage       : $cas9->info;
  Purpose     : return info about a Cas9 object
				type species crispr_target_seq
  Returns     : Array of Strings
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub info {
    my ( $self, ) = @_;
    
    my @info = (
        $self->type,
        $self->species,
        $self->crispr_target_seq,
    );
    return @info;
}

=method crispr_target_seq

  Usage       : $cas9->crispr_target_seq;
  Purpose     : Returns the crispr_target_seq - combination of target_seq and PAM
  Returns     : String
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub crispr_target_seq {
    my ( $self, ) = @_;    
    return $self->target_seq . $self->PAM;
}

#_build_target_seq
#
#Usage       : $cas9->_build_target_seq;
#Purpose     : builder for target_seq attribute
#Returns     : String
#Parameters  : None
#Throws      : 
#Comments    : Uses species attribute to determine target_seq
#               Default: 'NNNNNNNNNNNNNNNNNN'

sub _build_target_seq {
    my ( $self, ) = @_;
    
    my %target_seq_for = (
        's_pyogenes' => 'NNNNNNNNNNNNNNNNNN',
    );
    
    if( exists $target_seq_for{ lc( $self->species ) } ){
        return $target_seq_for{ lc( $self->species ) };
    }
    else{
        return 'NNNNNNNNNNNNNNNNNN';
    }
}

#_build_PAM
#
#Usage       : $cas9->_build_PAM;
#Purpose     : builder for PAM attribute
#Returns     : String
#Parameters  : None
#Throws      : 
#Comments    : Uses species attribute to determine target_seq
#               Default: 'NGG'

sub _build_PAM {
	my ( $self, ) = @_;
	my %PAM_for = (
        's_pyogenes' => 'NGG',
	);
    
    if( exists $PAM_for{ lc( $self->species ) } ){
        return $PAM_for{ lc( $self->species ) };
    }
    else{
        return 'NGG';
    }
}

#_build_name
#
#Usage       : $cas9->_build_name;
#Purpose     : builder for name attribute
#Returns     : String
#Parameters  : None
#Throws      : 
#Comments    : Default value is vector-type

sub _build_name {
    my ( $self, ) = @_;
    return join(q{-}, $self->vector, $self->type, );
}

#_build_vector
#
#Usage       : $cas9->_build_vector;
#Purpose     : builder for vector attribute
#Returns     : String
#Parameters  : None
#Throws      : 
#Comments    : 
#Default     : 'pCS2'

sub _build_vector {
    my ( $self, ) = @_;
    return 'pCS2';
}


__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 SYNOPSIS
 
    use Crispr::Cas9;
    my $cas9 = Crispr::Cas9->new(
        type => 'ZfnCas9n',
        species => 's_pyogenes',
        target_seq => 'NNNNNNNNNNNNNNNNNN',
        PAM => 'NGG',
        vector => 'pCS2'
        name => 'pCS2-ZfnCas9n',
    );

    # get crispr target site
    $target_site = $cas9->crispr_target_seq();
    
    
=head1 DESCRIPTION
 
Objects of this class represent a Cas9 endonuclease.

=head1 DIAGNOSTICS

=over

=item Not a valid DNA sequence.

The supplied sequence must only contain the characters ACGTNRYSWMKBDHV.

=item method new called without Hash or Hashref.

The new method accepts as arguments either a Hash or HashRef. Calling it in any other way will give this error message.

=back

=head1 DEPENDENCIES
 
 Moose
 
=head1 INCOMPATIBILITIES
 

