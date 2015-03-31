## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::SubplexAdaptor;
## use critic

# ABSTRACT: SubplexAdaptor object - object for storing Subplex objects in and retrieving them from a SQL database

use namespace::autoclean;
use Moose;
use DateTime;
use Carp qw( cluck confess );
use English qw( -no_match_vars );
use List::MoreUtils qw( any );
use Crispr::DB::Subplex;

extends 'Crispr::DB::BaseAdaptor';

=method new

  Usage       : my $subplex_adaptor = Crispr::DB::SubplexAdaptor->new(
					db_connection => $db_connection,
                );
  Purpose     : Constructor for creating subplex adaptor objects
  Returns     : Crispr::DB::SubplexAdaptor object
  Parameters  :     db_connection => Crispr::DB::DBConnection object,
  Throws      : If parameters are not the correct type
  Comments    : The preferred method for constructing a SubplexAdaptor is to use the
                get_adaptor method with a previously constructed DBConnection object

=cut

=method plex_adaptor

  Usage       : $self->plex_adaptor();
  Purpose     : Getter for a plex_adaptor.
  Returns     : Crispr::DB::PlexAdaptor
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'plex_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::PlexAdaptor',
    lazy => 1,
    builder => '_build_plex_adaptor',
);

=method injection_pool_adaptor

  Usage       : $self->injection_pool_adaptor();
  Purpose     : Getter for a injection_pool_adaptor.
  Returns     : Crispr::DB::InjectionPoolAdaptor
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'injection_pool_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::InjectionPoolAdaptor',
    lazy => 1,
    builder => '_build_injection_pool_adaptor',
);


=method store

  Usage       : $subplex = $subplex_adaptor->store( $subplex );
  Purpose     : Store a subplex in the database
  Returns     : Crispr::DB::Subplex object
  Parameters  : Crispr::DB::Subplex object
  Throws      : If argument is not a Subplex object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : 

=cut

sub store {
    my ( $self, $subplex, ) = @_;
	# make an arrayref with this one subplex and call store_subplexes
	my @subplexes = ( $subplex );
	my $subplexes = $self->store_subplexes( \@subplexes );
	
	return $subplexes->[0];
}

=method store_subplex

  Usage       : $subplex = $subplex_adaptor->store_subplex( $subplex );
  Purpose     : Store a subplex in the database
  Returns     : Crispr::DB::Subplex object
  Parameters  : Crispr::DB::Subplex object
  Throws      : If argument is not a Subplex object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : Synonym for store

=cut

sub store_subplex {
    my ( $self, $subplex, ) = @_;
	return $self->store( $subplex );
}

=method store_subplexes

  Usage       : $subplexes = $subplex_adaptor->store_subplexes( $subplexes );
  Purpose     : Store a set of subplexes in the database
  Returns     : ArrayRef of Crispr::DB::Subplex objects
  Parameters  : ArrayRef of Crispr::DB::Subplex objects
  Throws      : If argument is not an ArrayRef
                If objects in ArrayRef are not Crispr::DB::Subplex objects
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None
   
=cut

sub store_subplexes {
    my ( $self, $subplexes, ) = @_;
    my $dbh = $self->connection->dbh();
    
	confess "Supplied argument must be an ArrayRef of Subplex objects.\n" if( ref $subplexes ne 'ARRAY');
	foreach my $subplex ( @{$subplexes} ){
        if( !ref $subplex || !$subplex->isa('Crispr::DB::Subplex') ){
            confess "Argument must be Crispr::DB::Subplex objects.\n";
        }
    }
    
    my $add_subplex_statement = "insert into subplex values( ?, ?, ?, ? );"; 
    
    $self->connection->txn(  fixup => sub {
        my $sth = $dbh->prepare($add_subplex_statement);
        foreach my $subplex ( @{$subplexes} ){
            # check plex exists
            my $plex_id;
            my ( $plex_check_statement, $plex_params );
            if( !defined $subplex->plex ){
                confess join("\n", "One of the Subplex objects does not contain a Plex object.",
                    "This is required to able to add the subplex to the database.", ), "\n";
            }
            else{
                if( defined $subplex->plex->db_id ){
                    $plex_check_statement = "select count(*) from plex where plex_id = ?;";
                    $plex_params = [ $subplex->plex->db_id ];
                }
                elsif( defined $subplex->plex->plex_name ){
                    $plex_check_statement = "select count(*) from plex where plex_name = ?;";
                    $plex_params = [ $subplex->plex->plex_name ];
                }
            }
            # check plex exists in db
            if( !$self->check_entry_exists_in_db( $plex_check_statement, $plex_params ) ){
                # try storing it
                if( defined $subplex->plex->plex_name && defined $subplex->plex->run_id ){
                    $self->plex_adaptor->store( $subplex->plex );
                }
            }
            else{
                # need db_id
                if( !$plex_id ){
                    my $plex = $self->plex_adaptor->fetch_by_name( $subplex->plex->plex_name );
                    $plex_id = $plex->db_id;
                }
            }
            
            # check injection pool for id and check it exists in the db
            my $injection_id;
            my ( $inj_pool_check_statement, $inj_pool_params );
            if( !defined $subplex->injection_pool ){
                confess join("\n", "One of the Subplex objects does not contain a InjectionPool object.",
                    "This is required to able to add the subplex to the database.", ), "\n";
            }
            else{
                if( defined $subplex->injection_pool->db_id ){
                    $inj_pool_check_statement = "select count(*) from injection where injection_id = ?;";
                    $inj_pool_params = [ $subplex->injection_pool->db_id ];
                }
                elsif( defined $subplex->injection_pool->pool_name ){
                    $inj_pool_check_statement = "select count(*) from injection i, injection_pool ip where injection_name = ? and ip.crRNA_id is NOT NULL;";
                    $inj_pool_params = [ $subplex->injection_pool->pool_name ];
                }
            }
            # check injection_pool exists in db
            if( !$self->check_entry_exists_in_db( $inj_pool_check_statement, $inj_pool_params ) ){
                # try storing it
                $self->injection_pool_adaptor->store( $subplex->injection_pool );
            }
            else{
                # need db_id
                if( !$injection_id ){
                    my $injection_pool = $self->injection_pool_adaptor->fetch_by_name( $subplex->injection_pool->pool_name );
                    $injection_id = $injection_pool->db_id;
                }
            }
            
            # add subplex
            $sth->execute(
                $subplex->db_id, $plex_id,
                $subplex->plate_num, $injection_id,
            );
            
            my $last_id;
            $last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'subplex', 'subplex_id' );
            $subplex->db_id( $last_id );
        }
        $sth->finish();
    } );
    
    return $subplexes;
}

=method fetch_by_id

  Usage       : $subplexes = $subplex_adaptor->fetch_by_id( $subplex_id );
  Purpose     : Fetch a subplex given its database id
  Returns     : Crispr::DB::Subplex object
  Parameters  : crispr-db subplex_id - Int
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_by_id {
    my ( $self, $id ) = @_;
    my $subplex = $self->_fetch( 'subplex_id = ?;', [ $id ] )->[0];
    if( !$subplex ){
        confess "Couldn't retrieve subplex, $id, from database.\n";
    }
    return $subplex;
}

=method fetch_by_ids

  Usage       : $subplexes = $subplex_adaptor->fetch_by_ids( \@subplex_ids );
  Purpose     : Fetch a list of subplexes given a list of db ids
  Returns     : Arrayref of Crispr::DB::Subplex objects
  Parameters  : Arrayref of crispr-db subplex ids
  Throws      : If no rows are returned from the database for one of ids
                If too many rows are returned from the database for one of ids
  Comments    : None

=cut

sub fetch_by_ids {
    my ( $self, $ids ) = @_;
	my @subplexes;
    foreach my $id ( @{$ids} ){
        push @subplexes, $self->fetch_by_id( $id );
    }
	
    return \@subplexes;
}

=method fetch_all_by_plex_id

  Usage       : $subplexes = $subplex_adaptor->fetch_all_by_plex_id( $plex_id );
  Purpose     : Fetch an subplex given a plex database id
  Returns     : Crispr::DB::Subplex object
  Parameters  : Int
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_plex_id {
    my ( $self, $plex_id ) = @_;
    my $subplexes = $self->_fetch( 'plex_id = ?;', [ $plex_id ] );
    if( !$subplexes ){
        confess join(q{ }, "Couldn't retrieve subplexes for plex id, ",
                     $plex_id, "from database.\n" );
    }
    return $subplexes;
}

=method fetch_all_by_plex

  Usage       : $subplexes = $subplex_adaptor->fetch_all_by_plex( $plex );
  Purpose     : Fetch an subplex given a Plex object
  Returns     : Crispr::DB::Subplex object
  Parameters  : Crispr::DB::Plex object
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_plex {
    my ( $self, $plex ) = @_;
    return $self->fetch_all_by_plex_id( $plex->db_id );
}

=method fetch_all_by_injection_id

  Usage       : $subplexes = $subplex_adaptor->fetch_all_by_injection_id( $inj_id );
  Purpose     : Fetch an subplex given an InjectionPool object
  Returns     : Crispr::DB::Subplex object
  Parameters  : Crispr::DB::InjectionPool object
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_injection_id {
    my ( $self, $inj_id ) = @_;
    my $subplexes = $self->_fetch( 'injection_id = ?;', [ $inj_id ] );
    if( !$subplexes ){
        confess join(q{ }, "Couldn't retrieve subplexes for injection id,",
                     $inj_id, "from database.\n" );
    }
    return $subplexes;
}

=method fetch_all_by_injection_pool

  Usage       : $subplexes = $subplex_adaptor->fetch_all_by_injection_pool( $inj_pool );
  Purpose     : Fetch an subplex given an InjectionPool object
  Returns     : Crispr::DB::Subplex object
  Parameters  : Crispr::DB::InjectionPool object
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_injection_pool {
    my ( $self, $inj_pool ) = @_;
    return $self->fetch_all_by_injection_id( $inj_pool->db_id );
}

#_fetch
#
#Usage       : $subplex = $self->_fetch( \@fields );
#Purpose     : Fetch a Subplex object from the database with arbitrary parameteres
#Returns     : ArrayRef of Crispr::DB::Subplex objects
#Parameters  : where_clause => Str (SQL where clause)
#               where_parameters => ArrayRef of parameters to bind to sql statement
#Throws      : 
#Comments    : 

my %subplex_cache; # Cache for Subplex objects. HashRef keyed on subplex_id (db_id)
sub _fetch {
    my ( $self, $where_clause, $where_parameters ) = @_;
    my $dbh = $self->connection->dbh();
    
    my $sql = <<'END_SQL';
        SELECT
            subplex_id, plex_id,
            plate_num, injection_id
        FROM subplex
END_SQL

    if ($where_clause) {
        $sql .= 'WHERE ' . $where_clause;
    }
    
    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $subplex_id, $plex_id,
            $plate_num, $injection_id, );
    
    $sth->bind_columns( \( $subplex_id, $plex_id,
            $plate_num, $injection_id, ) );

    my @subplexes = ();
    while ( $sth->fetch ) {
        
        my $subplex;
        if( !exists $subplex_cache{ $subplex_id } ){
            # fetch plex by plex_id
            my $plex = $self->plex_adaptor->fetch_by_id( $plex_id );
            # fetch injection pool by id
            my $injection_pool = $self->injection_pool_adaptor->fetch_by_id( $injection_id );
            
            $subplex = Crispr::DB::Subplex->new(
                db_id => $subplex_id,
                plex => $plex,
                plate_num => $plate_num,
                injection_pool => $injection_pool,
            );
            $subplex_cache{ $subplex_id } = $subplex;
        }
        else{
            $subplex = $subplex_cache{ $subplex_id };
        }
        
        push @subplexes, $subplex;
    }

    return \@subplexes;    
}

=method delete_subplex_from_db

  Usage       : $subplex_adaptor->delete_subplex_from_db( $subplex );
  Purpose     : Delete a subplex from the database
  Returns     : Crispr::DB::Subplex object
  Parameters  : Crispr::DB::Subplex object
  Throws      : 
  Comments    : Not implemented yet.

=cut

sub delete_subplex_from_db {
	#my ( $self, $subplex ) = @_;
	
	# first check subplex exists in db
	
	# delete primers and primer pairs
	
	# delete transcripts
	
	# if subplex has talen pairs, delete tale and talen pairs

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

#_build_plex_adaptor

  #Usage       : $plex_adaptor = $self->_build_plex_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::PlexAdaptor
  #Returns     : Crispr::DB::PlexAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_plex_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'plex' );
}

#_build_injection_pool_adaptor

  #Usage       : $injection_pool_adaptor = $self->_build_injection_pool_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::InjectionPoolAdaptor
  #Returns     : Crispr::DB::InjectionPoolAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_injection_pool_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'injection_pool' );
}



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
  
    my $subplex_adaptor = $db_adaptor->get_adaptor( 'subplex' );
    
    # store a subplex object in the db
    $subplex_adaptor->store( $subplex );
    
    # retrieve a subplex by id
    my $subplex = $subplex_adaptor->fetch_by_id( '214' );
  
    # retrieve a list of subplexes by date
    my $subplexes = $subplex_adaptor->fetch_by_date( '2015-04-27' );
    

=head1 DESCRIPTION
 
 A SubplexAdaptor is an object used for storing and retrieving Subplex objects in an SQL database.
 The recommended way to use this module is through the DBAdaptor object as shown above.
 This allows a single open connection to the database which can be shared between multiple database adaptors.
 
=head1 DIAGNOSTICS
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
=head1 DEPENDENCIES
 
 
=head1 INCOMPATIBILITIES
 
