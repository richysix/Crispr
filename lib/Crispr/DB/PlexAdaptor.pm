## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::PlexAdaptor;
## use critic

# ABSTRACT: PlexAdaptor object - object for storing Plex objects in and retrieving them from a SQL database

use namespace::autoclean;
use Moose;
use DateTime;
use Carp qw( cluck confess );
use English qw( -no_match_vars );
use List::MoreUtils qw( any );
use Crispr::DB::Plex;

extends 'Crispr::DB::BaseAdaptor';

=method new

  Usage       : my $plex_adaptor = Crispr::DB::PlexAdaptor->new(
					db_connection => $db_connection,
                );
  Purpose     : Constructor for creating plex adaptor objects
  Returns     : Crispr::DB::PlexAdaptor object
  Parameters  :     db_connection => Crispr::DB::DBConnection object,
  Throws      : If parameters are not the correct type
  Comments    : The preferred method for constructing a PlexAdaptor is to use the
                get_adaptor method with a previously constructed DBConnection object

=cut

=method store

  Usage       : $plex = $plex_adaptor->store( $plex );
  Purpose     : Store a plex in the database
  Returns     : Crispr::DB::Plex object
  Parameters  : Crispr::DB::Plex object
  Throws      : If argument is not a Plex object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : 

=cut

sub store {
    my ( $self, $plex, ) = @_;
	# make an arrayref with this one plex and call store_plexes
	my @plexes = ( $plex );
	my $plexes = $self->store_plexes( \@plexes );
	
	return $plexes->[0];
}

=method store_plex

  Usage       : $plex = $plex_adaptor->store_plex( $plex );
  Purpose     : Store a plex in the database
  Returns     : Crispr::DB::Plex object
  Parameters  : Crispr::DB::Plex object
  Throws      : If argument is not a Plex object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : Synonym for store

=cut

sub store_plex {
    my ( $self, $plex, ) = @_;
	return $self->store( $plex );
}

=method store_plexes

  Usage       : $plexes = $plex_adaptor->store_plexes( $plexes );
  Purpose     : Store a set of plexes in the database
  Returns     : ArrayRef of Crispr::DB::Plex objects
  Parameters  : ArrayRef of Crispr::DB::Plex objects
  Throws      : If argument is not an ArrayRef
                If objects in ArrayRef are not Crispr::DB::Plex objects
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None
   
=cut

sub store_plexes {
    my ( $self, $plexes, ) = @_;
    my $dbh = $self->connection->dbh();
    
	confess "Supplied argument must be an ArrayRef of Plex objects.\n" if( ref $plexes ne 'ARRAY');
	foreach my $plex ( @{$plexes} ){
        if( !ref $plex || !$plex->isa('Crispr::DB::Plex') ){
            confess "Argument must be Crispr::DB::Plex objects.\n";
        }
    }
	
    my $add_plex_statement = "insert into plex values( ?, ?, ?, ?, ? );"; 
    
    $self->connection->txn(  fixup => sub {
        my $sth = $dbh->prepare($add_plex_statement);
        foreach my $plex ( @{$plexes} ){
            # add plex
            $sth->execute(
                $plex->db_id, $plex->plex_name,
                $plex->run_id, $plex->analysis_started,
                $plex->analysis_finished,
            );
            
            my $last_id;
            $last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'plex', 'plex_id' );
            $plex->db_id( $last_id );
        }
        $sth->finish();
    } );
    
    return $plexes;
}

=method fetch_by_id

  Usage       : $plexes = $plex_adaptor->fetch_by_id( $plex_id );
  Purpose     : Fetch a plex given its database id
  Returns     : Crispr::DB::Plex object
  Parameters  : crispr-db plex_id - Int
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_by_id {
    my ( $self, $id ) = @_;
    my $plex = $self->_fetch( 'plex_id = ?;', [ $id ] )->[0];
    if( !$plex ){
        confess "Couldn't retrieve plex, $id, from database.\n";
    }
    return $plex;
}

=method fetch_by_ids

  Usage       : $plexes = $plex_adaptor->fetch_by_ids( \@plex_ids );
  Purpose     : Fetch a list of plexes given a list of db ids
  Returns     : Arrayref of Crispr::DB::Plex objects
  Parameters  : Arrayref of crispr-db plex ids
  Throws      : If no rows are returned from the database for one of ids
                If too many rows are returned from the database for one of ids
  Comments    : None

=cut

sub fetch_by_ids {
    my ( $self, $ids ) = @_;
	my @plexes;
    foreach my $id ( @{$ids} ){
        push @plexes, $self->fetch_by_id( $id );
    }
	
    return \@plexes;
}

=method fetch_by_name

  Usage       : $plexes = $plex_adaptor->fetch_by_name( $plex_name );
  Purpose     : Fetch an plex given a plex name
  Returns     : Crispr::DB::Plex object
  Parameters  : crispr-db plex name - Str
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_by_name {
    my ( $self, $name ) = @_;
    my $plex = $self->_fetch( 'plex_name = ?;', [ lc($name) ] )->[0];
    if( !$plex ){
        confess "Couldn't retrieve plex, $name, from database.\n";
    }
    return $plex;
}

#_fetch
#
#Usage       : $plex = $self->_fetch( \@fields );
#Purpose     : Fetch a Plex object from the database with arbitrary parameteres
#Returns     : ArrayRef of Crispr::DB::Plex objects
#Parameters  : where_clause => Str (SQL where clause)
#               where_parameters => ArrayRef of parameters to bind to sql statement
#Throws      : 
#Comments    : 

my %plex_cache; # Cache for Plex objects. HashRef keyed on plex_id (db_id)
sub _fetch {
    my ( $self, $where_clause, $where_parameters ) = @_;
    my $dbh = $self->connection->dbh();
    
    my $sql = <<'END_SQL';
        SELECT
            plex_id, plex_name, run_id,
            analysis_started, analysis_finished
        FROM plex
END_SQL

    if ($where_clause) {
        $sql .= 'WHERE ' . $where_clause;
    }
    
    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $plex_id, $plex_name, $run_id,
            $analysis_started, $analysis_finished, );
    
    $sth->bind_columns( \( $plex_id, $plex_name, $run_id,
            $analysis_started, $analysis_finished, ) );

    my @plexes = ();
    while ( $sth->fetch ) {
        
        my $plex;
        if( !exists $plex_cache{ $plex_id } ){
            $plex = Crispr::DB::Plex->new(
                db_id => $plex_id,
                plex_name => $plex_name,
                run_id => $run_id,
                analysis_started => $analysis_started,
                analysis_finished => $analysis_finished,
            );
            $plex_cache{ $plex_id } = $plex;
        }
        else{
            $plex = $plex_cache{ $plex_id };
        }
        
        push @plexes, $plex;
    }

    return \@plexes;    
}

=method delete_plex_from_db

  Usage       : $plex_adaptor->delete_plex_from_db( $plex );
  Purpose     : Delete a plex from the database
  Returns     : Crispr::DB::Plex object
  Parameters  : Crispr::DB::Plex object
  Throws      : 
  Comments    : Not implemented yet.

=cut

sub delete_plex_from_db {
	#my ( $self, $plex ) = @_;
	
	# first check plex exists in db
	
	# delete primers and primer pairs
	
	# delete transcripts
	
	# if plex has talen pairs, delete tale and talen pairs

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

#_build_target_adaptor

  #Usage       : $crRNAs = $crRNA_adaptor->_build_target_adaptor( $well, $type );
  #Purpose     : Internal method to create a new Crispr::DB::TargetAdaptor
  #Returns     : Crispr::DB::TargetAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod
 
=head1 SYNOPSIS
 
    use Crispr::DB::DBAdaptor;
    my $db_adaptor = Crispr::DB::DBAdaptor->new(
        host => 'HOST',
        port => 'PORT',
        dbname => 'DATABASE',
        user => 'USER',
        pass => 'PASS',
        connection => $dbc,
    );
  
    my $plex_adaptor = $db_adaptor->get_adaptor( 'plex' );
    
    # store a plex object in the db
    $plex_adaptor->store( $plex );
    
    # retrieve a plex by id
    my $plex = $plex_adaptor->fetch_by_id( '214' );
  
    # retrieve a list of plexes by date
    my $plexes = $plex_adaptor->fetch_by_date( '2015-04-27' );
    

=head1 DESCRIPTION
 
 A PlexAdaptor is an object used for storing and retrieving Plex objects in an SQL database.
 The recommended way to use this module is through the DBAdaptor object as shown above.
 This allows a single open connection to the database which can be shared between multiple database adaptors.
 
=head1 DIAGNOSTICS
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
=head1 DEPENDENCIES
 
 
=head1 INCOMPATIBILITIES
 
