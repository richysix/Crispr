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
                    type => 'sgRNA',
                    stock_concentration => $concentration,
                    injection_concentration => $inj_conc,
                    made_by => $made_by,
                    date => $date,
                    well => $well,
                );
  Purpose     : Constructor for creating GuideRNAPrep objects
  Returns     : Crispr::DB::GuideRNAPrep object
  Parameters  : crRNA => Crispr::crRNA,
                type => Str,
                stock_concentration => Num,
                injection_concentration => Num,
                made_by => Str,
                date => DateTime OR Str ('yyyy-mm-dd'),
                well => Labware::Well
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method db_id

  Usage       : $gRNA_prep->db_id;
  Purpose     : Getter/Setter for GuideRNAPrep db_id attribute
  Returns     : Crispr::db_id object
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'db_id' => (
    is => 'rw',
    isa => 'Maybe[Int]',
);

=method crRNA

  Usage       : $gRNA_prep->crRNA;
  Purpose     : Getter/Setter for GuideRNAPrep crRNA attribute
  Returns     : Crispr::crRNA object
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'crRNA' => (
    is => 'rw',
    isa => 'Crispr::crRNA',
    required => 1,
    handles => {
        crRNA_id => 'crRNA_id',
    },
);

=method type

  Usage       : $gRNA_prep->type;
  Purpose     : Getter for GuideRNAPrep type attribute
  Returns     : Num
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'type' => (
    is => 'ro',
    isa => enum( [ qw{ sgRNA tracrRNA } ] ),
    required => 1,
    default => 'sgRNA',
);

=method stock_concentration

  Usage       : $gRNA_prep->stock_concentration;
  Purpose     : Getter for GuideRNAPrep stock_concentration attribute
  Returns     : Num
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'stock_concentration' => (
    is => 'ro',
    isa => 'Num',
    required => 1,
);

=method injection_concentration

  Usage       : $gRNA_prep->injection_concentration;
  Purpose     : Getter for GuideRNAPrep injection_concentration attribute
  Returns     : Num
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'injection_concentration' => (
    is => 'rw',
    isa => 'Maybe[Num]',
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

=method well

  Usage       : $gRNA_prep->well;
  Purpose     : Getter/Setter for well attribute
  Returns     : Labware::Well object
  Parameters  : Labware::Well
  Throws      : 
  Comments    : 

=cut

has 'well' => (
    is => 'rw',
    isa => 'Maybe[Labware::Well]',
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
        crRNA => $crRNA_object,
        type => 'sgRNA',
        stock_concentration => 50.7,
        injection_concentration => 10,
        made_by => $made_by,
        date => $date,
        well => $well,
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
 

