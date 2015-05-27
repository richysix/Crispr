## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::InjectionPool;
## use critic

# ABSTRACT: InjectionPool object - representing a pool of Cas9/CRISPR guide RNAs for injection/transfection

use warnings;
use strict;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use DateTime;

with 'Crispr::SharedMethods';

=method new

  Usage       : my $inj = Crispr::InjectionPool->new(
					db_id => undef,
                    pool_name => 'inj01',
					cas9_prep => $cas9_prep,
					cas9_conc => 200,
                    date => '2014-09-30',
                    line_injected => 'line1',
                    line_raised => 'line2',
                    sorted_by => 'cr_1',
                    guideRNAs => \@crisprs,
                );
  Purpose     : Constructor for creating InjectionPool objects
  Returns     : Crispr::InjectionPool object
  Parameters  : db_id => Int,
                pool_name => Str,
                cas9_prep => Crispr::DB:Cas9Prep,
                cas9_conc => Num,
                date => DateTime || Str,
                line_injected => Str,
                line_raised => Str,
                sorted_by => Str,
                guideRNAs => ArrayRef[ Crispr::DB::GuideRNAPrep ],

  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method db_id

  Usage       : $inj->db_id;
  Purpose     : Getter/Setter for InjectionPool db_id attribute
  Returns     : Int (can be undef)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'db_id' => (
    is => 'rw',
    isa => 'Maybe[Int]',
);

=method pool_name

  Usage       : $inj->pool_name;
  Purpose     : Getter for InjectionPool pool_name attribute
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'pool_name' => (
    is => 'ro',
    isa => 'Str',
);

=method cas9_prep

  Usage       : $inj->cas9_prep;
  Purpose     : Getter for cas9_prep attribute
  Returns     : Crispr::DB::Cas9Prep object
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'cas9_prep' => (
    is => 'ro',
    isa => 'Crispr::DB::Cas9Prep',
    writer => '_set_cas9_prep',
);

=method cas9_conc

  Usage       : $inj->cas9_conc;
  Purpose     : Getter for cas9_conc attribute
  Returns     : Num
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'cas9_conc' => (
    is => 'ro',
	isa =>  'Num',
);

=method date

  Usage       : $inj->date;
  Purpose     : Getter for date attribute
  Returns     : DateTime
  Parameters  : Either DateTime object or Str of form yyyy-mm-dd
  Throws      : If input is given
  Comments    : 

=cut

has 'date' => (
    is => 'ro',
    isa => 'Maybe[DateTime]',
    lazy => 1,
    builder => '_build_date',
);

=method line_injected

  Usage       : $inj->line_injected;
  Purpose     : Getter for line_injected attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'line_injected' => (
    is => 'ro',
    isa => 'Str',
);

=method line_raised

  Usage       : $inj->line_raised;
  Purpose     : Getter/Setter for line_raised attribute
  Returns     : Str (Can be undef)
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'line_raised' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

=method sorted_by

  Usage       : $inj->sorted_by;
  Purpose     : Getter for sorted_by attribute
  Returns     : Str (can be undef)
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'sorted_by' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

=method guideRNAs

  Usage       : $inj->guideRNAs;
  Purpose     : Getter for guideRNAs attribute
  Returns     : Str (can be undef)
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'guideRNAs' => (
    is => 'rw',
    isa => 'ArrayRef[Crispr::DB::GuideRNAPrep]',
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

=method info

  Usage       : $inj->info;
  Purpose     : returns information about an InjectionPool object
  Returns     : Array
  Parameters  : None
  Throws      : 
  Comments    : undef attributes are returned as the string 'NULL'

=cut


sub info {
    my ( $self, ) = @_;
    return (
        $self->db_id || 'NULL',
        $self->pool_name,
        $self->cas9_conc,
        $self->date || 'NULL',
        $self->line_injected,
        $self->line_raised || 'NULL',
        $self->sorted_by || 'NULL',
    );
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 SYNOPSIS
 
    use Crispr::InjectionPool;
    my $inj = Crispr::InjectionPool->new(
        db_id => undef,
        pool_name => 'inj01',
        cas9_prep => $cas9_prep,
        cas9_conc => 200,
        date => '2014-09-30',
        line_injected => 'line1',
        line_raised => 'line2',
        guideRNAs => \@crisprs,
    );    
    
=head1 DESCRIPTION
 
Objects of this class represent a pool of reagents used for injection/transfection containing Cas9 and guideRNAs.

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
 

