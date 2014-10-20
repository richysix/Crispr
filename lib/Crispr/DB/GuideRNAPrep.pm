## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::GuideRNAPrep;
## use critic

# ABSTRACT: GuideRNAPrep object - represents a prep of a specific guide RNA

use warnings;
use strict;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use DateTime;

with 'Crispr::SharedMethods';

=method new

  Usage       : my $gRNA_prep = Crispr::DB::GuideRNAPrep->new(
                    crRNA => $crRNA_object,
                    concentration => $concentration,
                    made_by => $made_by,
                    date => $date,
                );
  Purpose     : Constructor for creating Sample objects
  Returns     : Crispr::DB::GuideRNAPrep object
  Parameters  : crRNA => Crispr::crRNA,
                concentration => Num,
                made_by => Str,
                date => DateTime OR Str ('yyyy-mm-dd'),
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method crRNA

  Usage       : $gRNA_prep->crRNA;
  Purpose     : Getter/Setter for Sample crRNA attribute
  Returns     : Crispr::crRNA object
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'crRNA' => (
    is => 'rw',
    isa => 'Crispr::crRNA',
    required => 1,
);

=method concentration

  Usage       : $gRNA_prep->concentration;
  Purpose     : Getter for Sample concentration attribute
  Returns     : Num
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'concentration' => (
    is => 'ro',
    isa => 'Num',
    required => 1,
);

=method made_by

  Usage       : $gRNA_prep->made_by;
  Purpose     : Getter for made_by attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'made_by' => (
    is => 'ro',
    isa => 'Str',
    required => 1,
);

=method date

  Usage       : $gRNA_prep->date;
  Purpose     : Getter for date attribute
  Returns     : Str 'yyyy-mm-dd'
  Parameters  : DateTime OR Str 'yyyy-mm-dd'
  Throws      : If input is given
  Comments    : 

=cut

has 'date' => (
    is => 'ro',
	isa =>  'DateTime',
    required => 1,
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
 
    use Crispr::DB::GuideRNAPrep;
    my $gRNA_prep = Crispr::DB::GuideRNAPrep->new(
        crRNA => $crRNA,
        concentration => 10,
        made_by => 'crispr_test',
        date => '2014-10-13',
    );
    
=head1 DESCRIPTION
 
Objects of this class represent represent an RNA preparation of a CRISPR guide RNA

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
 

