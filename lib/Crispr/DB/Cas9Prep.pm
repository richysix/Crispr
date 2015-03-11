## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::Cas9Prep;
## use critic

# ABSTRACT: Cas9Prep object - representing a specific prep of the Cas9 endonuclease

use warnings;
use strict;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use DateTime;

with 'Crispr::SharedMethods';

=method new

  Usage       : my $cas9_prep = Crispr::Cas9Prep->new(
					db_id => undef,
					cas9 => $cas9,
					prep_type => rna,
					made_by => 'crispr_test_user',
                    date => '2014-09-30',
                    notes => 'Some interesting notes',
                );
  Purpose     : Constructor for creating Cas9Prep objects
  Returns     : Crispr::Cas9Prep object
  Parameters  : db_id => INT
                cas9 => Crispr::Cas9
                prep_type => Str, ('rna', 'dna' or 'protein')
                made_by => Str
                date => DateTime or Str ('yyyy-mm-dd')
                notes => Str
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method db_id

  Usage       : $cas9_prep->db_id;
  Purpose     : Getter for Cas9Prep db_id attribute
  Returns     : Int (can be undef)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'db_id' => (
    is => 'rw',
    isa => 'Maybe[Int]',
);

=method cas9

  Usage       : $cas9_prep->cas9;
  Purpose     : Getter for cas9 attribute
  Returns     : Crispr::Cas9 object
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'cas9' => (
    is => 'ro',
    isa => 'Crispr::Cas9',
    handles => {
        cas9_db_id => 'db_id',
        type => 'type',
        species => 'species',
        name => 'name',
        target_seq => 'target_seq',
        PAM => 'PAM',
        crispr_target_seq => 'crispr_target_seq',
    },
);

=method prep_type

  Usage       : $cas9_prep->prep_type;
  Purpose     : Getter for associated prep_type
  Returns     : String ('dna', 'rna' or 'protein')
  Parameters  : None
  Throws      : If input is given
                If input is not one of dna, rna or protein
  Comments    : 

=cut

has 'prep_type' => (
    is => 'ro',
	isa => enum( [ qw{ dna rna protein } ] ),
    default => 'rna',
);

=method made_by

  Usage       : $cas9_prep->made_by;
  Purpose     : Getter for made_by attribute
  Returns     : String
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'made_by' => (
    is => 'ro',
    isa => 'Str',
);

=method date

  Usage       : $target->date;
  Purpose     : Getter/Setter for date attribute
  Returns     : DateTime
  Parameters  : Either DateTime object or Str of form yyyy-mm-dd
  Throws      : 
  Comments    : 

=cut

has 'date' => (
    is => 'rw',
    isa => 'Maybe[DateTime]',
    lazy => 1,
    builder => '_build_date',
);

=method notes

  Usage       : $cas9->notes;
  Purpose     : Getter for notes attribute
  Returns     : String (Default: undef)
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'notes' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

around BUILDARGS => sub{
    my $method = shift;
    my $self = shift;
    my %args;
	
    if( !ref $_[0] ){
		for( my $i = 0; $i < scalar @_; $i += 2 ){
			my $k = $_[$i];
			my $v = $_[$i+1];
            if( $k eq 'date' ){
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
        if( exists $_[0]->{'date'} ){
            if( defined $_[0]->{'date'} &&
                ( !ref $_[0]->{'date'} || ref $_[0]->{'date'} ne 'DateTime' ) ){
                my $date_obj = $self->_parse_date( $_[0]->{'date'} );
                $_[0]->{'date'} = $date_obj;
            }
        }
        return $self->$method( $_[0] );
    }
    else{
        confess "method new called without Hash or Hashref.\n";
    }	
};

# around date
# This is to accept either a DateTime object or a string in form yyyy-mm-dd
#   and also to return a string instead of the DateTime object
around 'date' => sub {
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
 
    use Crispr::Cas9Prep;
    my $cas9_prep = Crispr::Cas9Prep->new(
        db_id => undef,
        cas9 => $cas9,
        prep_type => rna,
        made_by => 'crispr_test_user',
        date => '2014-09-30',
    );
    
    
=head1 DESCRIPTION
 
Objects of this class represent a specific prep of Cas9 made by a specific user on a given date.

=head1 DIAGNOSTICS

=over

=item method new called without Hash or Hashref.

The new method accepts as arguments either a Hash or HashRef. Calling it in any other way will give this error message.

=item The date supplied is not a valid format.

The date attribute must be supplied either as a DateTime object or a string of the format 'yyyy-mm-dd'.

=back

=head1 DEPENDENCIES
 
 Moose
 
=head1 INCOMPATIBILITIES
 

