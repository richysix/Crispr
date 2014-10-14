## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::SharedMethods;
## use critic

# ABSTRACT: SharedMethods Role - provides methods share across modules

use namespace::autoclean;
use Moose::Role;
use DateTime;

#_parse_date
#
#Usage       : $self->_parse_date( '2014-03-21' );
#Purpose     : Converts dates in form yyyy-mm-dd into DateTime object
#Returns     : DateTime object
#Parameters  : String
#Throws      : If date is not in correct format
#Comments    :

sub _parse_date {
    my ( $self, $input ) = @_;
    my $date_obj;
    
    if( $input =~ m/\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/xms ){
        $date_obj = DateTime->new(
            year       => $1,
            month      => $2,
            day        => $3,
        );
    }
    else{
        confess "The date supplied is not a valid format\n";
    }
    return $date_obj;
}

#_build_date
#
#Usage       : $crRNA->_build_date( '2014-03-21' );
#Purpose     : Internal method to get today's date as a DateTime object
#Returns     : DateTime object
#Parameters  : String
#Throws      : If date is not in correct format
#Comments    :

sub _build_date {
    my ( $self, ) = @_;
    return DateTime->now()
}

1;

__END__

=head1 SYNOPSIS
 
    with 'SharedMethods';
  
  
=head1 DESCRIPTION
 
This module is a Moose Role used to add common methods to Crispr modules.

The methods added are:

=over

=item *     _parse_date         Converts dates in form yyyy-mm-dd into DateTime object

=item *     _build_date         Returns a DateTime object for today's date

=back
 
