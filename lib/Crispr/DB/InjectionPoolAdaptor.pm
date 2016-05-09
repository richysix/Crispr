## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::InjectionPoolAdaptor;

## use critic

# ABSTRACT: InjectionPoolAdaptor object - object for storing InjectionPool objects in and retrieving them from a SQL database

use namespace::autoclean;
use Moose;
use DateTime;
use Carp qw( cluck confess );
use English qw( -no_match_vars );
use List::MoreUtils qw( any );
use Crispr::Cas9;
use Crispr::DB::Cas9Prep;
use Crispr::DB::InjectionPool;

extends 'Crispr::DB::BaseAdaptor';

=method new

  Usage       : my $injection_pool_adaptor = Crispr::DB::InjectionPoolAdaptor->new(
					db_connection => $db_connection,
                );
  Purpose     : Constructor for creating injection_pool adaptor objects
  Returns     : Crispr::DB::InjectionPoolAdaptor object
  Parameters  :     db_connection => Crispr::DB::DBConnection object,
  Throws      : If parameters are not the correct type
  Comments    : The preferred method for constructing a InjectionPoolAdaptor is to use the
                get_adaptor method with a previously constructed DBConnection object

=cut

# cache for injection_pool objects from db
has '_injection_pool_cache' => (
	is => 'ro',
	isa => 'HashRef',
    init_arg => undef,
    writer => '_set_injection_pool_cache',
    default => sub { return {}; },
);

=method store

  Usage       : $injection_pool = $injection_pool_adaptor->store( $injection_pool );
  Purpose     : Store an injection_pool in the database
  Returns     : Crispr::DB::InjectionPool object
  Parameters  : Crispr::DB::InjectionPool object
  Throws      : If argument is not a InjectionPool object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : 

=cut

sub store {
    my ( $self, $injection_pool, ) = @_;
	# make an arrayref with this one injection_pool and call store_injection_pools
	my @injection_pools = ( $injection_pool );
	my $injection_pools = $self->store_injection_pools( \@injection_pools );
	
	return $injection_pools->[0];
}

=method store_injection_pool

  Usage       : $injection_pool = $injection_pool_adaptor->store_injection_pool( $injection_pool );
  Purpose     : Store an injection_pool in the database
  Returns     : Crispr::DB::InjectionPool object
  Parameters  : Crispr::DB::InjectionPool object
  Throws      : If argument is not a InjectionPool object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : Synonym for store

=cut

sub store_injection_pool {
    my ( $self, $injection_pool, ) = @_;
	return $self->store( $injection_pool );
}

=method store_injection_pools

  Usage       : $injection_pools = $injection_pool_adaptor->store_injection_pools( $injection_pools );
  Purpose     : Store a set of injection_pools in the database
  Returns     : ArrayRef of Crispr::DB::InjectionPool objects
  Parameters  : ArrayRef of Crispr::DB::InjectionPool objects
  Throws      : If argument is not an ArrayRef
                If objects in ArrayRef are not Crispr::DB::InjectionPool objects
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None
   
=cut

sub store_injection_pools {
    my ( $self, $injection_pools, ) = @_;
    my $dbh = $self->connection->dbh();
    
	confess "Supplied argument must be an ArrayRef of InjectionPool objects.\n" if( ref $injection_pools ne 'ARRAY');
	foreach my $inj_pool ( @{$injection_pools} ){
        if( !ref $inj_pool || !$inj_pool->isa('Crispr::DB::InjectionPool') ){
            confess "Argument must be Crispr::DB::InjectionPool objects.\n";
        }
        # also check that injections pools have cas9 prep
        if( !defined $inj_pool->cas9_prep ){
            confess "One of the InjectionPools does not contain a Cas9 object.\n";
        }
        elsif( !defined $inj_pool->cas9_prep->db_id ){
            confess "One of the InjectionPools has a Cas9 object with no db_id!\n";
            #if( !defined $inj_pool->cas9_prep->type || !defined $inj_pool->cas9_prep->prep_type ||
            #    !defined $inj_pool->cas9_prep->made_by || !defined $inj_pool->cas9_prep->date ){
            #    confess "One of the InjectionPools contains a Cas9 object without a db_id or enough information to find it.\n";
            #}
            #else{
            #    eval{
            #        my $cas9_prep = $self->cas9_prep_adaptor->fetch_without_db_id( $inj_pool->cas9_prep );
            #    };
            #    if( $EVAL_ERROR ){
            #        
            #    }
            #    $inj_pool->_set_cas9_prep(  );
            #}
        }
        
        # and check guide RNAs
        if( !defined $inj_pool->guideRNAs ){
            confess "One of the InjectionPools does not contain any guide RNAs.\n";
        }
        else{
            if( any { !defined $_->crRNA_id } @{ $inj_pool->guideRNAs } ){
                confess "One of the InjectionPools contains a guide RNA without a db_id.\n";
            }
        }
        
    }
	
    # need to check that cas9 prep and guide RNAs exist in the db.
    my $check_cas9_statement = "select count(*) from cas9_prep where cas9_prep_id = ?;";
    my $check_guideRNA_statement = "select count(*) from guideRNA_prep where guideRNA_prep_id = ?;";
    my $check_crRNA_statement = "select count(*) from crRNA where crRNA_id = ?;";
    my $check_inj_statement = "SELECT count(*) from injection WHERE injection_name = ?;";
    
    my $add_inj_statement = "insert into injection values( ?, ?, ?, ?, ?, ?, ?, ? );"; 
    my $add_gRNA_statement = "insert into injection_pool values( ?, ?, ?, ? );"; 
    
    $self->connection->txn(  fixup => sub {
        my $sth;
        foreach my $injection_pool ( @{$injection_pools} ){
            # check whether injection already exists in the db
            if( $self->check_entry_exists_in_db( $check_inj_statement, [ $injection_pool->pool_name, ] ) ){
                die "ALREADY EXISTS";
            }
            
            $sth = $dbh->prepare($add_inj_statement);
            # check cas9 prep exists
            eval{
                if( !$self->check_entry_exists_in_db( $check_cas9_statement, [ $injection_pool->cas9_prep->db_id, ] ) ){
                    #try and store it
                    $self->cas9_prep_adaptor->store( $injection_pool->cas9_prep );
                }
            };
            if( $EVAL_ERROR ){
                if( $EVAL_ERROR =~ m/TOO\sMANY\sITEMS/xms ){
                    confess "Found more than one Cas9 prep with the same database id!\n",
                        $EVAL_ERROR, "\n";
                }
                else{
                    confess $EVAL_ERROR, "\n";
                }
            }
            # check guide RNAs exist
            foreach my $guide_RNA ( @{$injection_pool->guideRNAs } ){
                if( !$self->check_entry_exists_in_db( $check_guideRNA_statement, [ $guide_RNA->db_id, ] ) ){
                    confess "Couldn't find guideRNA prep in database";
                }
                if( !$self->check_entry_exists_in_db( $check_crRNA_statement, [ $guide_RNA->crRNA_id, ] ) ){
                    confess "Couldn't find crRNA in database";
                }
            }
            
            # add injection
            $sth->execute($injection_pool->db_id, $injection_pool->pool_name,
                $injection_pool->cas9_prep->db_id, $injection_pool->cas9_conc,
                $injection_pool->date,
                $injection_pool->line_injected, $injection_pool->line_raised,
                $injection_pool->sorted_by,
            );
            
            my $last_id;
            $last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'injection', 'injection_id' );
            $injection_pool->db_id( $last_id );
            
            # add guideRNAs
            $sth = $dbh->prepare($add_gRNA_statement);
            foreach my $guide_RNA ( @{$injection_pool->guideRNAs } ){
                $sth->execute(
                    $injection_pool->db_id,
                    $guide_RNA->crRNA_id,
                    $guide_RNA->db_id,
                    $guide_RNA->injection_concentration,
                );
            }
        }
        
        $sth->finish() if $sth;
    } );
    
    return $injection_pools;
}

=method fetch_by_id

  Usage       : $injection_pools = $injection_pool_adaptor->fetch_by_id( $injection_pool_id );
  Purpose     : Fetch a injection_pool given its database id
  Returns     : Crispr::DB::InjectionPool object
  Parameters  : crispr-db injection_id - Int
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_by_id {
    my ( $self, $id ) = @_;
    my $injection_pool = $self->_fetch( 'injection_id = ?', [ $id ] )->[0];
    #if( !$injection_pool ){
    #    confess "Couldn't retrieve injection_pool, $id, from database.\n";
    #}
    return $injection_pool;
}

=method fetch_by_ids

  Usage       : $injection_pools = $injection_pool_adaptor->fetch_by_ids( \@injection_pool_ids );
  Purpose     : Fetch a list of injection_pools given a list of db ids
  Returns     : Arrayref of Crispr::DB::InjectionPool objects
  Parameters  : Arrayref of crispr-db injection_pool ids
  Throws      : If no rows are returned from the database for one of ids
                If too many rows are returned from the database for one of ids
  Comments    : None

=cut

sub fetch_by_ids {
    my ( $self, $ids ) = @_;
	my @injection_pools;
    foreach my $id ( @{$ids} ){
        push @injection_pools, $self->fetch_by_id( $id );
    }
	
    return \@injection_pools;
}

=method fetch_by_name

  Usage       : $injection_pools = $injection_pool_adaptor->fetch_by_name( $injection_pool_name );
  Purpose     : Fetch an injection_pool given a injection_pool name
  Returns     : Crispr::DB::InjectionPool object
  Parameters  : crispr-db injection_pool name - Str
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_by_name {
    my ( $self, $name ) = @_;
    my $injection_pool = $self->_fetch( 'injection_name = ?', [ $name ] )->[0];
    #if( !$injection_pool ){
    #    confess "Couldn't retrieve injection_pool, $name, from database.\n";
    #}
    return $injection_pool;
}

=method fetch_all_by_date

  Usage       : $injection_pools = $injection_pool_adaptor->fetch_all_by_date( $date );
  Purpose     : Fetch a list of injection_pools given a date
  Returns     : ArrayRef of Crispr::DB::InjectionPool objects
  Parameters  : date => Str ('yyyy-mm-dd')
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_all_by_date  {
    my ( $self, $date ) = @_;
    my $injection_pools = $self->_fetch( 'i.date = ?', [ $date ] );
    #if( scalar @{$injection_pools} == 0 ){
    #    confess "There are no injection_pools for the date, $date, in the database.\n";
    #}
    return $injection_pools;
}

=method fetch_all_by_crRNAs

  Usage       : $injection_pools = $injection_pool_adaptor->fetch_all_by_crRNAs( \@crRNAs );
  Purpose     : Fetch a list of injection_pools given a list of crRNAs
  Returns     : ArrayRef of Crispr::DB::InjectionPool objects
  Parameters  : ArrayRef of Crispr::crRNA objects
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_all_by_crRNAs {
    my ( $self, $crRNAs ) = @_;
    my $dbh = $self->connection->dbh();
    
    my $where_clause = 'ip.crRNA_id IN (' .
        join(q{,}, ('?') x scalar @{$crRNAs} ) .
        ')';
    my $where_parameters = [ map { $_->crRNA_id } @{$crRNAs} ];
    my $sql = <<'END_SQL';
        SELECT
            i.injection_id, injection_name, cas9_concentration,
            i.date, line_injected, line_raised, sorted_by,
            cp.cas9_prep_id, cp.prep_type, cp.made_by, cp.date, cp.notes,
            c.cas9_id, c.name, c.type, c.vector, c.species,
            ip.crRNA_id, ip.guideRNA_prep_id, ip.guideRNA_concentration
        FROM injection i, cas9_prep cp, cas9 c, injection_pool ip 
        WHERE i.cas9_prep_id = cp.cas9_prep_id AND
            cp.cas9_id = c.cas9_id AND
            i.injection_id = ip.injection_id
END_SQL

    if ($where_clause) {
        $sql .= 'AND ' . $where_clause;
    }

    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $injection_id, $injection_name, $cas9_concentration,
        $inj_date, $line_injected, $line_raised, $sorted_by,
        $cas9_prep_id, $prep_type, $made_by, $date, $notes,
        $cas9_id, $cas9_name, $type, $vector, $species,
        $crRNA_id, $guideRNA_prep_id, $guideRNA_concentration,
    );
    
    $sth->bind_columns( \( $injection_id, $injection_name, $cas9_concentration,
        $inj_date, $line_injected, $line_raised, $sorted_by,
        $cas9_prep_id, $prep_type, $made_by, $date, $notes,
        $cas9_id, $cas9_name, $type, $vector, $species,
        $crRNA_id, $guideRNA_prep_id, $guideRNA_concentration, ) );

    my @injection_pools = ();
    while ( $sth->fetch ) {
        
        my $cas9_prep = $self->cas9_prep_adaptor->_make_new_cas9_prep_from_db(
            [ $cas9_prep_id, $prep_type, $made_by, $date, $notes,
                $cas9_id, $cas9_name, $type, $vector, $species, ],
        );
        
        # check if it already exists in the injections pools array
        my @pools = grep { $_->db_id eq $injection_id } @injection_pools;
        # if not, then make a new injection pool/ get it from the cache
        if( !@pools ){        
            my $inj_pool;
            if( !exists $self->_injection_pool_cache->{ $injection_id } ){
                $inj_pool = Crispr::DB::InjectionPool->new(
                    db_id => $injection_id,
                    pool_name => $injection_name,
                    cas9_prep => $cas9_prep,
                    cas9_conc => $cas9_concentration,
                    date => $inj_date,
                    line_injected => $line_injected,
                    line_raised => $line_raised,
                    sorted_by => $sorted_by,
                );
                my $inj_pool_cache = $self->_injection_pool_cache;
                $inj_pool_cache->{ $injection_id } = $inj_pool;
                $self->_set_injection_pool_cache( $inj_pool_cache );
            }
            else{
                $inj_pool = $self->_injection_pool_cache->{ $injection_id };
            }
            $inj_pool->guideRNAs(
                $self->guideRNA_prep_adaptor->fetch_all_by_injection_pool( $inj_pool )
            );
            
            push @injection_pools, $inj_pool;
        }
    }

    return \@injection_pools;    
}

=method fetch_all_by_gene

  Usage       : $injection_pools = $injection_pool_adaptor->fetch_all_by_gene( 'gene_name' );
  Purpose     : Fetch a list of injection_pools given a gene name
  Returns     : ArrayRef of Crispr::DB::InjectionPool objects
  Parameters  : gene_name => Str (can be a gene_name, gene_id or target_name)
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_all_by_gene  {
    my ( $self, $gene ) = @_;
    my ($targets, $crRNAs, $injection_pools, );
    
    $targets = $self->target_adaptor->fetch_all_by_target_name_gene_id_gene_name( $gene );
    if( @{$targets} ){
        $crRNAs = $self->crRNA_adaptor->fetch_all_by_targets( $targets );
    }
    #else{
    #    die 'NO TARGETS';
    #}
    if( @{$crRNAs} ){
       $injection_pools = $self->crRNA_adaptor->fetch_all_by_crRNAs( $crRNAs );
    }
    #else{
    #    die 'NO CR_RNAS';
    #}
    #if( scalar @{$injection_pools} == 0 ){
    #    die "NO INJECTION_POOLS";
    #}
    return $injection_pools;
}

#_fetch
#
#Usage       : $injection_pool = $self->_fetch( \@fields );
#Purpose     : Fetch InjectionPool objects from the database with arbitrary parameteres
#Returns     : ArrayRef of Crispr::DB::InjectionPool objects
#Parameters  : where_clause => Str (SQL where conditions)
#               where_parameters => ArrayRef of parameters to bind to sql statement
#Throws      : 
#Comments    : 

sub _fetch {
    my ( $self, $where_clause, $where_parameters ) = @_;
    my $dbh = $self->connection->dbh();
    
    my $sql = <<'END_SQL';
        SELECT
            i.injection_id, injection_name, cas9_concentration,
            i.date, line_injected, line_raised, sorted_by,
            cp.cas9_prep_id, cp.prep_type, cp.made_by, cp.date, cp.notes,
            c.cas9_id, c.name, c.type, c.vector, c.species
        FROM injection i, cas9_prep cp, cas9 c 
        WHERE i.cas9_prep_id = cp.cas9_prep_id AND
            cp.cas9_id = c.cas9_id 
END_SQL

    if ($where_clause) {
        $sql .= 'AND ' . $where_clause;
    }

    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $injection_id, $injection_name, $cas9_concentration,
        $inj_date, $line_injected, $line_raised, $sorted_by,
        $cas9_prep_id, $prep_type, $made_by, $date, $notes,
        $cas9_id, $cas9_name, $type, $vector, $species,
    );
    
    $sth->bind_columns( \( $injection_id, $injection_name, $cas9_concentration,
        $inj_date, $line_injected, $line_raised, $sorted_by,
        $cas9_prep_id, $prep_type, $made_by, $date, $notes,
        $cas9_id, $cas9_name, $type, $vector, $species, ) );

    my @injection_pools = ();
    while ( $sth->fetch ) {
        
        my $cas9_prep = $self->cas9_prep_adaptor->_make_new_cas9_prep_from_db(
            [ $cas9_prep_id, $prep_type, $made_by, $date, $notes,
                $cas9_id, $cas9_name, $type, $vector, $species, ],
        );
        
        my $inj_pool;
        if( !exists $self->_injection_pool_cache->{ $injection_id } ){
            $inj_pool = Crispr::DB::InjectionPool->new(
                db_id => $injection_id,
                pool_name => $injection_name,
                cas9_prep => $cas9_prep,
                cas9_conc => $cas9_concentration,
                date => $inj_date,
                line_injected => $line_injected,
                line_raised => $line_raised,
                sorted_by => $sorted_by,
            );
            my $inj_pool_cache = $self->_injection_pool_cache;
            $inj_pool_cache->{ $injection_id } = $inj_pool;
            $self->_set_injection_pool_cache( $inj_pool_cache );
        }
        else{
            $inj_pool = $self->_injection_pool_cache->{ $injection_id };
        }
        $inj_pool->guideRNAs(
            $self->guideRNA_prep_adaptor->fetch_all_by_injection_pool( $inj_pool )
        );
        
        push @injection_pools, $inj_pool;
    }

    return \@injection_pools;    
}

=method delete_injection_pool_from_db

  Usage       : $injection_pool_adaptor->delete_injection_pool_from_db( $injection_pool );
  Purpose     : Delete a injection_pool from the database
  Returns     : Crispr::DB::InjectionPool object
  Parameters  : Crispr::DB::InjectionPool object
  Throws      : 
  Comments    : Not implemented yet.

=cut

sub delete_injection_pool_from_db {
	#my ( $self, $injection_pool ) = @_;
	
	# first check injection_pool exists in db
	
	# delete primers and primer pairs
	
	# delete transcripts
	
	# if injection_pool has talen pairs, delete tale and talen pairs

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
        connection => $dbc,
    );
  
    my $injection_pool_adaptor = $db_connection->get_adaptor( 'injection_pool' );
    
    # store a injection_pool object in the db
    $injection_pool_adaptor->store( $injection_pool );
    
    # retrieve a injection_pool by id
    my $injection_pool = $injection_pool_adaptor->fetch_by_id( '214' );
  
    # retrieve a list of injection_pools by date
    my $injection_pools = $injection_pool_adaptor->fetch_by_date( '2015-04-27' );
    

=head1 DESCRIPTION
 
 A InjectionPoolAdaptor is an object used for storing and retrieving InjectionPool objects in an SQL database.
 The recommended way to use this module is through the DBAdaptor object as shown above.
 This allows a single open connection to the database which can be shared between multiple database adaptors.
 
=head1 DIAGNOSTICS
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
=head1 DEPENDENCIES
 
 
=head1 INCOMPATIBILITIES
 
