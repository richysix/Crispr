## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::Cas9Adaptor;
## use critic

# ABSTRACT: Cas9Adaptor object - object for storing Cas9 objects in and retrieving them from a SQL database

use namespace::autoclean;
use Moose;
use DateTime;
use Carp qw( cluck confess );
use English qw( -no_match_vars );
use Crispr::Cas9;

extends 'Crispr::DB::BaseAdaptor';

=method new

  Usage       : my $cas9_adaptor = Crispr::DB::Cas9Adaptor->new(
					db_connection => $db_connection,
                );
  Purpose     : Constructor for creating cas9 adaptor objects
  Returns     : Crispr::DB::Cas9Adaptor object
  Parameters  :     db_connection => Crispr::DB::DBConnection object,
  Throws      : If parameters are not the correct type
  Comments    : The preferred method for constructing a Cas9Adaptor is to use the
                get_adaptor method with a previously constructed DBConnection object

=cut

=method store

  Usage       : $cas9 = $cas9_adaptor->store( $cas9 );
  Purpose     : Store a cas9 object in the database
  Returns     : Crispr::Cas9 object
  Parameters  : Crispr::Cas9 object
  Throws      : If argument is not a Cas9 object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : 

=cut

sub store {
    my ( $self, $cas9, ) = @_;
	# make an arrayref with this one cas9 and call store_cas9s
	my @cas9s = ( $cas9 );
	my $cas9s = $self->store_cas9s( \@cas9s );
	
	return $cas9s->[0];
}

=method store_cas9

  Usage       : $cas9 = $cas9_adaptor->store_cas9( $cas9 );
  Purpose     : Store a cas9 in the database
  Returns     : Crispr::Cas9 object
  Parameters  : Crispr::Cas9 object
  Throws      : If argument is not a Cas9 object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : Synonym for store

=cut

sub store_cas9 {
    my ( $self, $cas9, ) = @_;
	return $self->store( $cas9 );
}

=method store_cas9s

  Usage       : $cas9s = $cas9_adaptor->store_cas9s( $cas9s );
  Purpose     : Store a set of cas9s in the database
  Returns     : ArrayRef of Crispr::Cas9 objects
  Parameters  : ArrayRef of Crispr::Cas9 objects
  Throws      : If argument is not an ArrayRef
                If objects in ArrayRef are not Crispr::Cas9 objects
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None
   
=cut

sub store_cas9s {
    my $self = shift;
    my $cas9s = shift;
    my $dbh = $self->connection->dbh();
    
	confess "Supplied argument must be an ArrayRef of Cas9 objects.\n" if( ref $cas9s ne 'ARRAY');
	foreach ( @{$cas9s} ){
        if( !ref $_ || !$_->isa('Crispr::Cas9') ){
            confess "Argument must be Crispr::Cas9 objects.\n";
        }
    }
	
    my $statement = "insert into cas9 values( ?, ?, ? );"; 
    
    $self->connection->txn(  fixup => sub {
		my $sth = $dbh->prepare($statement);
		
		foreach my $cas9 ( @$cas9s ){
			$sth->execute($cas9->db_id,
                $cas9->type,
				$cas9->plasmid_name,
            );
			
			my $last_id;
			$last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'cas9', 'cas9_id' );
			$cas9->db_id( $last_id );
		}
		
		$sth->finish();
    } );
    
    return $cas9s;
}

=method fetch_by_id

  Usage       : $cas9 = $cas9_adaptor->fetch_by_id( $cas9_id );
  Purpose     : Fetch a cas9 given its database id
  Returns     : Crispr::Cas9 object
  Parameters  : crispr-db cas9_id - Int
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_by_id {
    my ( $self, $id ) = @_;

    my $cas9 = $self->_fetch( 'cas9_id = ?', [ $id ] )->[0];
    
    if( !$cas9 ){
        confess "Couldn't retrieve cas9, $id, from database.\n";
    }
    return $cas9;
}

=method fetch_by_ids

  Usage       : $cas9s = $cas9_adaptor->fetch_by_ids( \@cas9_ids );
  Purpose     : Fetch a list of cas9s given a list of db ids
  Returns     : Arrayref of Crispr::Cas9 objects
  Parameters  : Arrayref of crispr-db cas9 ids
  Throws      : If no rows are returned from the database for one of ids
  Comments    : None

=cut

sub fetch_by_ids {
    my ( $self, $ids ) = @_;
	my @cas9s;
    foreach my $id ( @{$ids} ){
        push @cas9s, $self->fetch_by_id( $id );
    }
	
    return \@cas9s;
}

=method fetch_by_type

  Usage       : $cas9s = $cas9_adaptor->fetch_by_type( $cas9 );
  Purpose     : Fetch a cas9 object by type
  Returns     : Crispr::Cas9 object
  Parameters  : type => Str
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_by_type {
    my ( $self, $type ) = @_;

    my $cas9 = $self->_fetch( 'type = ?', [ $type, ] )->[0];
    
    if( !$cas9 ){
        confess "Couldn't retrieve cas9 from database.\n";
    }
    return $cas9;
}

=method fetch_by_plasmid_name

  Usage       : $cas9s = $cas9_adaptor->fetch_by_plasmid_name( $cas9_type, $date );
  Purpose     : Fetch a cas9 object by plasmid name
  Returns     : Crispr::Cas9 object
  Parameters  : plasmid name => Str
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_by_plasmid_name {
    my ( $self, $plasmid_name ) = @_;
    
    my $statement = "plasmid_name = ?;";
    my $cas9s = $self->_fetch( $statement, [ $plasmid_name, ], )->[0];
    return $cas9s;
}

#_fetch
#
#Usage       : $cas9 = $self->_fetch( $where_clause, $where_parameters );
#Purpose     : Fetch Cas9 objects from the database with arbitrary parameteres
#Returns     : ArrayRef of Crispr::Cas9 objects
#Parameters  : where_clause => Str (SQL where conditions)
#               where_parameters => ArrayRef of parameters to bind to sql statement
#Throws      : 
#Comments    :

my %cas9_cache;
sub _fetch {
    my ( $self, $where_clause, $where_parameters ) = @_;
    my $dbh = $self->connection->dbh();
    
    my $sql = <<'END_SQL';
        SELECT
			cas9_id,
			type,
			plasmid_name
        FROM cas9
END_SQL

    if ($where_clause) {
        $sql .= 'WHERE ' . $where_clause;
    }

    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $cas9_id, $type, $plasmid_name, );
    
    $sth->bind_columns( \( $cas9_id, $type, $plasmid_name, ) );

    my @cas9s = ();
    while ( $sth->fetch ) {
        my $cas9;
        if( !exists $cas9_cache{ $cas9_id } ){
            $cas9 = Crispr::Cas9->new(
                db_id => $cas9_id,
                type => $type,
                plasmid_name => $plasmid_name,
            );
            $cas9_cache{ $cas9_id } = $cas9;
        }
        else{
            $cas9 = $cas9_cache{ $cas9_id };
        }
        
        push @cas9s, $cas9;
    }

    return \@cas9s;    
}

#_make_new_cas9_from_db
#
#Usage       : $cas9 = $self->_make_new_cas9_from_db( \@fields );
#Purpose     : Create a new Crispr::DB::Cas9 object from a db entry
#Returns     : Crispr::DB::Cas9 object
#Parameters  : ArrayRef of Str
#Throws      : 
#Comments    : Expects fields to be in table order ie db_id, cas9_type, prep_type, made_by, date

sub _make_new_cas9_from_db {
    my ( $self, $fields ) = @_;
    my $cas9;
	
    if( !exists $cas9_cache{ $fields->[0] } ){
        my %args = (
            db_id => $fields->[0],
            type => $fields->[1],
            pasmid_name => $fields->[2],
        );
        
        $cas9 = Crispr::Cas9->new( %args );
        $cas9_cache{ $fields->[0] } = $cas9;
    }
    else{
        $cas9 = $cas9_cache{ $fields->[0] };
    }
	
    return $cas9;
}

sub delete_cas9_from_db {
	#my ( $self, $cas9 ) = @_;
	
	# first check cas9 exists in db
	
	# delete primers and primer pairs
	
	# delete transcripts
	
	# if cas9 has talen pairs, delete tale and talen pairs

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
  
    my $cas9_adaptor = $db_connection->get_adaptor( 'cas9' );
    
    # store a cas9 object in the db
    $cas9_adaptor->store( $cas9 );
    
    # retrieve a cas9 by id
    my $cas9 = $cas9_adaptor->fetch_by_id( '214' );
  
    # retrieve a cas9 by combination of type and date
    my $cas9 = $cas9_adaptor->fetch_by_type_and_date( 'cas9_dnls_native', '2015-04-27' );
    

=head1 DESCRIPTION
 
 A Cas9Adaptor is an object used for storing and retrieving Cas9 objects in an SQL database.
 The recommended way to use this module is through the DBAdaptor object as shown above.
 This allows a single open connection to the database which can be shared between multiple database adaptors.
 
=head1 DIAGNOSTICS
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
=head1 DEPENDENCIES
 
 
=head1 INCOMPATIBILITIES
 
