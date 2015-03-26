package Crispr::Plate;
use namespace::autoclean;
use Moose;
use Moose::Util::TypeConstraints;
use DateTime;

extends 'Labware::Plate';

has 'plate_id' => (
    is => 'rw',
    isa => 'Maybe[Int]',
);

has 'plate_category' => (
    is => 'rw',
    isa => enum( [qw{ crispr cloning_oligos expression_construct
        t7_hairpin_oligos t7_fill-in_oligos guideRNA_prep pcr_primers
        kaspar_assays samples }] ),
);

has [ 'ordered', 'received' ] => (
    is => 'rw',
    isa => 'Maybe[DateTime]',
);

around BUILDARGS => sub{
    my $method = shift;
    my $self = shift;
    my %args;
    
    if( !ref $_[0] ){
        for( my $i = 0; $i < scalar @_; $i += 2){
            my $k = $_[$i];
            my $v = $_[$i+1];
            if( $k eq 'ordered' || $k eq 'received' ){
                if( defined $v && ref $v ne 'DateTime' ){
                    my $date_obj = $self->_parse_date( $v );
                    $v = $date_obj;
                }
            }
            $args{ $k } = $v;
        }
        return $self->$method( \%args );
    }
    elsif( ref $_[0] eq 'HASH' ){
        if( exists $_[0]->{'ordered'} ){
            if( defined $_[0]->{'ordered'} && ref $_[0]->{'ordered'} ne 'DateTime' ){
                my $date_obj = $self->_parse_date( $_[0]->{'ordered'} );
                $_[0]->{'ordered'} = $date_obj;
            }
        }
        if( exists $_[0]->{'received'} ){
            if( defined $_[0]->{'received'} && ref $_[0]->{'received'} ne 'DateTime' ){
                my $date_obj = $self->_parse_date( $_[0]->{'received'} );
                $_[0]->{'received'} = $date_obj;
            }
        }
        return $self->$method( $_[0] );
    }
    else{
        confess "method new called without Hash or Hashref.\n";
    }
};

around 'ordered' => sub {
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

around 'received' => sub {
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

__PACKAGE__->meta->make_immutable;
1;


###################
#my $plate = Crispr::Plate->new(
#    id => '1',
#    plate_name => 'CR-000001a',
#    plate_type => '96',
#    ordered => '2013-05-28',
#    received => '2013-06-04',
#);

