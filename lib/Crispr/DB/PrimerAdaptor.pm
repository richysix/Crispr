## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::PrimerAdaptor;
## use critic

# ABSTRACT: PrimerAdaptor object - object for storing Primer objects in and retrieving them from a SQL database

use namespace::autoclean;
use Moose;
use Crispr::Primer;
use Crispr::Plate;
use English qw( -no_match_vars );
use DateTime;
use Readonly;

extends 'Crispr::DB::BaseAdaptor';

=method new

  Usage       : my $primer_adaptor = Crispr::DB::PrimerAdaptor->new(
					db_connection => $db_connection,
                );
  Purpose     : Constructor for creating primer adaptor objects
  Returns     : Crispr::DB::PrimerAdaptor object
  Parameters  :     db_connection => Crispr::DB::DBConnection object,
  Throws      : If parameters are not the correct type
  Comments    : The preferred method for constructing a PrimerAdaptor is to use the
                get_adaptor method with a previously constructed DBConnection object

=cut

=method plate_adaptor

  Usage       : $primer_adaptor->plate_adaptor;
  Purpose     : Getter for a plate_adaptor
  Returns     : Crispr::DB::PlateAdaptor
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'plate_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::PlateAdaptor',
    lazy => 1,
    builder => '_build_plate_adaptor',
);

=method store

  Usage       : $primer_adaptor->store;
  Purpose     : method to store a primer in the database.
  Returns     : 1 on Success.
  Parameters  : Either Crispr::Primer
                Or Labware::Well containing Crispr::Primer object
  Throws      : If input is not correct type
  Comments    : 

=cut

sub store {
    my ( $self, $object ) = @_;
    my $dbh = $self->connection->dbh();
    
    # check object
    if( !$object ){
        confess "Argument to store is empty. An object must be supplied in order to add oligos to the database!\n";
    }
    else{
        # check if $object is either a Labware::Well object or a Crispr::Primer one
        if( !ref $object ||
           !($object->isa('Labware::Well') || $object->isa('Crispr::Primer') ) ){
            confess join(q{ },
                'The supplied object must be either a Labware::Well object',
                'or a Crispr::Primer object, not', ref $object, ), "!\n";
        }
    }
    
    my ( $primer, $plate_id, $well_id, );
    if( $object->isa('Labware::Well') ){
        $primer = $object->contents; 
        if( !$primer ){
            confess join(q{ },
                'The well is empty!',
                'A Crispr::Primer object must be supplied to add to the database',
            ), "!\n";
        }
        else{
            # check $primer is a Crispr::Primer object
            if( !ref $primer || !$primer->isa('Crispr::Primer') ){
                confess join(q{ },
                    'The supplied object must be a Crispr::Primer object, not',
                    ref $primer,
                ), "!\n";
            }
        }
        # check plate exists - check_entry_exists_in_db inherited from DBAttributes.
        my $check_plate_st = 'select count(*) from plate where plate_name = ?';
        if( !$self->check_entry_exists_in_db( $check_plate_st, [ $object->plate->plate_name ] ) ){
            # add plate to database
            $self->plate_adaptor->store( $object->plate );
        }
        if( !$object->plate->plate_id ){
            # fetch plate id from db
            $plate_id = $self->plate_adaptor->get_plate_id_from_name( $object->plate->plate_name );
        }
        else{
            $plate_id = $object->plate->plate_id;
        }
        $well_id = $object->position
    }
    if( $object->isa('Crispr::Primer') ){
        $primer = $object;
    }
    
    # check primer for tail
    my ( $primer_seq, $primer_tail ) = $self->_split_primer_into_seq_and_tail( $primer->sequence );
    
    # insert primer statement
    my $primer_statement = 'insert into primer values( ?, ?, ?, ?, ?, ?, ?, ?, ? );';
    
    $self->connection->txn(  fixup => sub {
        my $sth = $dbh->prepare($primer_statement); 
        $sth->execute(
            undef, $primer_seq,
            $primer->seq_region,
            $primer->seq_region_start, $primer->seq_region_end,
            $primer->seq_region_strand,
            $primer_tail,
            $plate_id, $well_id,
        );
        $sth->finish();
        my $last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'primer', 'primer_id' );
        $primer->primer_id( $last_id );
    } );
    return $primer;
}

#_split_primer_into_seq_and_tail

  #Usage       : ( $primer_sequence, $primer_tail, ) = $primer_adaptor->_split_primer_into_seq_and_tail( $p_sequence );
  #Purpose     : Internal method to split primer sequences into adaptor tail and main primer sequence
  #Returns     : Primer Sequence    => Str
  #              Adaptor Sequence   => Str
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _split_primer_into_seq_and_tail {
    my ( $self, $primer_sequence, ) = @_;
    my @tail_sequences = ( qw{ ACACTCTTTCCCTACACGACGCTCTTCCGATCT TCGGCATTCCTGCTGAACCGCTCTTCCGATCT } );
    
    my $primer_tail;
    my $matches;
    foreach( @tail_sequences ){
        if( $primer_sequence =~ m/\A $_/xms ){
            $matches++;
            $primer_tail = $_;
            $primer_sequence =~ s/\A $_//xms
        }
    }
    if( $matches && $matches > 1 ){
        die "Primer sequence matches more than one tail: $primer_sequence\n";
    }
    return ( $primer_sequence, $primer_tail, );
}

=method fetch_by_id

  Usage       : $primer_adaptor->fetch_by_id( '1' );
  Purpose     : Fetch a Primer from the database by its db_id.
  Returns     : Crispr::Primer
  Parameters  : Int
  Throws      : If No rows are returned
                If Too Many rows are returned
  Comments    : 

=cut

sub fetch_by_id {
    my ( $self, $primer_id ) = @_;
    my $dbh = $self->connection->dbh();
    # select statement
    my $statement = 'select * from primer where primer_id = ?';
    my ( $primers, $num_rows ) = $self->_fetch_primers_by_attributes( $statement, [ $primer_id ] );
    if( $num_rows == 0 ){
        "Couldn't find primer:$primer_id in database.\n";
    }
    elsif( $num_rows > 1 ){
        "Primer id:$primer_id should be unique, but got more than one row returned!\n";
    }
    else{
        return $primers->[0];
    }
}

=method fetch_by_name

  Usage       : $primer_adaptor->fetch_by_name( '24:103-130:1' );
  Purpose     : Fetch a Primer from the database by its name.
  Returns     : Crispr::Primer
  Parameters  : Str
  Throws      : If No rows are returned
                If Too Many rows are returned
  Comments    : 

=cut

sub fetch_by_name {
    my ( $self, $primer_name ) = @_;
    my $dbh = $self->connection->dbh();
    # parse primer name
    my ( $chr, $region, $strand ) = split /:/, $primer_name;
    my ( $start, $end ) = split /-/, $region;
    if( !$chr || !$region || !$strand || !$start || !$end ){
        confess "Cannot retrieve primer from database using primer name, $primer_name!\n";
    }
    
    # select statement
    my $statement = 'select * from primer where chr = ? and $start = ? and end = ? and strand = ?;';
    my ( $primers, $num_rows ) = $self->_fetch_primers_by_attributes( $statement, [ $chr, $start, $end, $strand ] );
    if( $num_rows == 0 ){
        "Couldn't find primer:$primer_name in database.\n";
    }
    elsif( $num_rows > 1 ){
        "Cannot retrieve primer from database using primer name, $primer_name!\n";
    }
    else{
        return $primers->[0];
    }
}

#_fetch_primers_by_attributes

  #Usage       : $primers = $primer_adaptor->_fetch_primers_by_attributes( $fetch_statement, $attributes  );
  #Purpose     : Internal method to fetch Crispr::Primers
  #Returns     : Crispr::Primers
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _fetch_primers_by_attributes {
    my ( $self, $fetch_statement, $attributes ) = @_;
    my $dbh = $self->connection->dbh();
    my $primers;
    my $num_rows = 0;
    $self->connection->txn(  fixup => sub {
        my $sth = $dbh->prepare($fetch_statement);
        $sth->execute( @{$attributes} );
        
        while( my @fields = $sth->fetchrow_array ){
            $num_rows++;
            my $primer = $self->_make_new_primer_from_db( \@fields );
            push @{$primers}, $primer;
        }
        $sth->finish();
    } );
    
    return ( $primers, $num_rows );
}

#_make_new_primer_from_db

  #Usage       : $crRNAs = $primer_adaptor->_make_new_primer_from_db( \@fields );
  #Purpose     : Internal method to create a new Crispr::Primer object from fields returned for the database
  #Returns     : Crispr::Primer
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _make_new_primer_from_db {
    my ( $self, $fields, ) = @_;
    
    my $primer = Crispr::Primer->new(
        primer_id => $fields->[0],
        sequence => $fields->[1],
        seq_region_name => $fields->[2],
        seq_region_start => $fields->[3],
        seq_region_end => $fields->[4],
        seq_region_strand => $fields->[5],
        plate_id => $fields->[6],
        well_id => $fields->[7],
    );
    
    return $primer;
}

#_build_plate_adaptor

  #Usage       : $crRNAs = $primer_adaptor->_build_plate_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::PlateAdaptor
  #Returns     : Crispr::DB::PlatePrepAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_plate_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'plate' );
}

=method driver

  Usage       : $self->driver();
  Purpose     : Getter for the db driver.
  Returns     : Str
  Parameters  : None
  Throws      : If driver is not either mysql or sqlite
  Comments    : 

=cut

=method host

  Usage       : $self->host();
  Purpose     : Getter for the db host name.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method port

  Usage       : $self->port();
  Purpose     : Getter for the db port.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method dbname

  Usage       : $self->dbname();
  Purpose     : Getter for the database (schema) name.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method user

  Usage       : $self->user();
  Purpose     : Getter for the db user name.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method pass

  Usage       : $self->pass();
  Purpose     : Getter for the db password.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method dbfile

  Usage       : $self->dbfile();
  Purpose     : Getter for the name of the SQLite database file.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method connection

  Usage       : $self->connection();
  Purpose     : Getter for the db Connection object.
  Returns     : DBIx::Connector
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method db_params

  Usage       : $self->db_params();
  Purpose     : method to return the db parameters as a HashRef.
                used internally to share the db params around Adaptor objects
  Returns     : HashRef
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method check_entry_exists_in_db

  Usage       : $self->check_entry_exists_in_db( $check_statement, $params );
  Purpose     : method used to check whether a particular entry exists in the database.
                Takes a MySQL statement of the form select count(*) from table where condition = ?;'
                and parameters
  Returns     : 1 if entry exists, undef if not
  Parameters  : check statement (Str)
                statement parameters (ArrayRef[Str])
  Throws      : 
  Comments    : 

=cut

=method fetch_rows_expecting_single_row

  Usage       : $self->fetch_rows_expecting_single_row( $sql_statement, $parameters );
  Purpose     : method to fetch a row from the database where the result should be unique.
  Returns     : ArrayRef
  Parameters  : MySQL statement (Str)
                Parameters (ArrayRef)
  Throws      : If no rows are returned from the database.
                If more than one row is returned.
  Comments    : 

=cut

=method fetch_rows_for_generic_select_statement

  Usage       : $self->fetch_rows_for_generic_select_statement( $sql_statement, $parameters );
  Purpose     : method to execute a generic select statement and return the rows from the db.
  Returns     : ArrayRef[Str]
  Parameters  : MySQL statement (Str)
                Parameters (ArrayRef)
  Throws      : If no rows are returned from the database.
  Comments    : 

=cut

=method _db_error_handling

  Usage       : $self->_db_error_handling( $error_message, $SQL_statement, $parameters );
  Purpose     : internal method to deal with error messages from the database.
  Returns     : Throws an exception that depends on the Adaptor type and
                the error message.
  Parameters  : Error Message (Str)
                MySQL statement (Str)
                Parameters (ArrayRef)
  Throws      : 
  Comments    : 

=cut

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod
 
=head1 SYNOPSIS
 
    use Crispr::DB::DBConnection;
    my $db_connection = Crispr::DB::DBConnection->new(
        host => 'HOST',
        port => 'PORT',
        dbname => 'DATABASE',
        user => 'USER',
        pass => 'PASS',
    );
  
    my $primer_adaptor = $db_connection->get_adaptor( 'primer' );
    
    # store a primer object in the db
    $primer_adaptor->store( $primer );
    
    # retrieve a primer by id
    my $primer = $primer_adaptor->fetch_by_id( '214' );
  
    # retrieve a primer by combination of type and date
    my $primer = $primer_adaptor->fetch_by_type_and_date( 'cas9_dnls_native', '2015-04-27' );
    

=head1 DESCRIPTION
 
 A PrimerAdaptor is an object used for storing and retrieving Primer objects in an SQL database.
 The recommended way to use this module is through the DBConnection object as shown above.
 This allows a single open connection to the database which can be shared between multiple database adaptors.
 
=head1 DIAGNOSTICS
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
=head1 DEPENDENCIES
 
 Moose
 
 Crispr::BaseAdaptor
 
=head1 INCOMPATIBILITIES
 
