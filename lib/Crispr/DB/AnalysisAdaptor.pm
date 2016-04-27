## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::AnalysisAdaptor;

## use critic

# ABSTRACT: AnalysisAdaptor object - object for storing Analysis objects in and retrieving them from a SQL database

use namespace::autoclean;
use Moose;
use DateTime;
use Carp qw( cluck confess );
use English qw( -no_match_vars );
use List::MoreUtils qw( any );
use Crispr::DB::Analysis;

extends 'Crispr::DB::BaseAdaptor';

=method new

  Usage       : my $analysis_adaptor = Crispr::DB::AnalysisAdaptor->new(
					db_connection => $db_connection,
                );
  Purpose     : Constructor for creating analysis adaptor objects
  Returns     : Crispr::DB::AnalysisAdaptor object
  Parameters  :     db_connection => Crispr::DB::DBConnection object,
  Throws      : If parameters are not the correct type
  Comments    : The preferred method for constructing a AnalysisAdaptor is to use the
                get_adaptor method with a previously constructed DBConnection object

=cut

# cache for analysis objects from db
has '_analysis_cache' => (
	is => 'ro',
	isa => 'HashRef',
    init_arg => undef,
    writer => '_set_analysis_cache',
    default => sub { return {}; },
);

=method store

  Usage       : $analysis = $analysis_adaptor->store( $analysis );
  Purpose     : Store a analysis in the database
  Returns     : Crispr::DB::Analysis object
  Parameters  : Crispr::DB::Analysis object
  Throws      : If argument is not a Analysis object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : 

=cut

sub store {
    my ( $self, $analysis, ) = @_;
	# make an arrayref with this one analysis and call store_analyses
	my @analyses = ( $analysis );
	my $analyses = $self->store_analyses( \@analyses );
	
	return $analyses->[0];
}

=method store_analysis

  Usage       : $analysis = $analysis_adaptor->store_analysis( $analysis );
  Purpose     : Store a analysis in the database
  Returns     : Crispr::DB::Analysis object
  Parameters  : Crispr::DB::Analysis object
  Throws      : If argument is not a Analysis object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : Synonym for store

=cut

sub store_analysis {
    my ( $self, $analysis, ) = @_;
	return $self->store( $analysis );
}

=method store_analyses

  Usage       : $analyses = $analysis_adaptor->store_analyses( $analyses );
  Purpose     : Store a set of analyses in the database
  Returns     : ArrayRef of Crispr::DB::Analysis objects
  Parameters  : ArrayRef of Crispr::DB::Analysis objects
  Throws      : If argument is not an ArrayRef
                If objects in ArrayRef are not Crispr::DB::Analysis objects
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None
   
=cut

sub store_analyses {
    my ( $self, $analyses, ) = @_;
    my $dbh = $self->connection->dbh();
    
	confess "Supplied argument must be an ArrayRef of Analysis objects.\n" if( ref $analyses ne 'ARRAY');
	foreach my $analysis ( @{$analyses} ){
        if( !ref $analysis || !$analysis->isa('Crispr::DB::Analysis') ){
            confess "Argument must be Crispr::DB::Analysis objects.\n";
        }
    }
    
    my $add_analysis_statement = "insert into analysis values( ?, ?, ?, ? );"; 
    my $add_analysis_info_statement = "insert into analysis_information values( ?, ?, ?, ?, ?, ? );"; 
    
    $self->connection->txn(  fixup => sub {
        my $sth = $dbh->prepare($add_analysis_statement);
        my $info_sth = $dbh->prepare($add_analysis_info_statement);
        foreach my $analysis ( @{$analyses} ){
            # check plex exists
            my $plex_id;
            my ( $plex_check_statement, $plex_params );
            if( !defined $analysis->plex ){
                confess join("\n", "One of the Analysis objects does not contain a Plex object.",
                    "This is required to able to add the analysis to the database.", ), "\n";
            }
            else{
                if( defined $analysis->plex->db_id ){
                    $plex_check_statement = "select count(*) from plex where plex_id = ?;";
                    $plex_params = [ $analysis->plex->db_id ];
                }
                elsif( defined $analysis->plex->plex_name ){
                    $plex_check_statement = "select count(*) from plex where plex_name = ?;";
                    $plex_params = [ $analysis->plex->plex_name ];
                }
            }
            # check plex exists in db
            if( !$self->check_entry_exists_in_db( $plex_check_statement, $plex_params ) ){
                # try storing it
                if( defined $analysis->plex->plex_name && defined $analysis->plex->run_id ){
                    $self->plex_adaptor->store( $analysis->plex );
                }
            }
            else{
                # need db_id
                if( !$plex_id ){
                    my $plex = $self->plex_adaptor->fetch_by_name( $analysis->plex->plex_name );
                    $plex_id = $plex->db_id;
                }
            }
            
            # check samples exist in the db
            if( !defined $analysis->samples ){
                    confess join("\n", "One of the Analysis objects does not contain any Sample objects.",
                        "This is required to able to add the analysis to the database.", ), "\n";
            }
            else{
                foreach my $sample ( $analysis->samples ){
                    my ( $sample_check_statement, $sample_params );
                    
                    if( defined $sample->db_id ){
                        $sample_check_statement = "select count(*) from sample where sample_id = ?;";
                        $sample_params = [ $sample->db_id ];
                    }
                    elsif( defined $sample->sample_name ){
                        $sample_check_statement = "select count(*) from sample where sample_name = ?;";
                        $sample_params = [ $sample->sample_name ];
                    }
                    # check sample exists in db
                    if( !$self->check_entry_exists_in_db( $sample_check_statement, $sample_params ) ){
                        # try storing it
                        $self->sample_adaptor->store( $sample );
                    }
                    else{
                        # need db_id
                        if( !defined $sample->db_id ){
                            my $sample_from_db = $self->sample_adaptor->fetch_by_name( $sample->sample_name );
                            $sample->db_id( $sample_from_db->db_id );
                        }
                    }
                }
            }
            
            # check primer_pairs exist in the db
            if( !defined $analysis->amplicons ){
                    confess join("\n", "One of the Analysis objects does not contain any PrimerPair objects.",
                        "This is required to able to add the analysis to the database.", ), "\n";
            }
            else{
                foreach my $primer_pair ( $analysis->amplicons ){
                    my ( $primer_pair_check_statement, $primer_pair_params );
                    if( defined $primer_pair->primer_pair_id ){
                        $primer_pair_check_statement = "select count(*) from primer_pair where primer_pair_id = ?;";
                        $primer_pair_params = [ $primer_pair->primer_pair_id ];
                    }
                    # TO DO: check primer pair by name
                    #elsif( defined $primer_pair->primer_pair_name ){
                    #    $primer_pair_check_statement = "select count(*) from primer_pair where primer_pair_name = ?;";
                    #    $primer_pair_params = [ $primer_pair->primer_pair_name ];
                    #}
                    else{
                        confess join("\n", 'One of the PrimerPair objects does not contain a database id.',
                                    'This is required to check that the primer pair exists in the database.'), "\n";
                    }
                    
                    # check primer_pair_pool exists in db
                    if( !$self->check_entry_exists_in_db( $primer_pair_check_statement, $primer_pair_params ) ){
                        # try storing it
                        $self->primer_pair_adaptor->store( $primer_pair );
                    }
                    #else{
                    #    # need db_id
                    #    if( !$primer_pair_id ){
                    #        my $primer_pair = $self->primer_pair_adaptor->fetch_by_name( $primer_pair->primer_pair_name );
                    #        $primer_pair_id = $primer_pair->db_id;
                    #    }
                    #}
                }
            }
            
            # add analysis and info
            $sth->execute(
                $analysis->db_id, $plex_id,
                $analysis->analysis_started,
                $analysis->analysis_finished,
            );
            my $last_id;
            $last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'analysis', 'analysis_id' );
            $analysis->db_id( $last_id );
            
            foreach my $sample_amplicon_obj ( @{ $analysis->info } ){
                foreach my $primer_pair ( $analysis->amplicons ){
                    # add to analysis info table
                    $info_sth->execute(
                        $analysis->db_id,
                        $sample_amplicon_obj->sample->db_id,
                        $primer_pair->primer_pair_id, 
                        $sample_amplicon_obj->barcode_id,
                        $sample_amplicon_obj->plate_number,
                        $sample_amplicon_obj->well_id,
                    );
                    
                }
            }
        }
        $sth->finish();
    } );
    
    return $analyses;
}

=method fetch_by_id

  Usage       : $analyses = $analysis_adaptor->fetch_by_id( $analysis_id );
  Purpose     : Fetch a analysis given its database id
  Returns     : Crispr::DB::Analysis object
  Parameters  : crispr-db analysis_id - Int
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_by_id {
    my ( $self, $id ) = @_;
    my $analysis = $self->_fetch( 'analysis_id = ?;', [ $id ] )->[0];
    if( !$analysis ){
        confess "Couldn't retrieve analysis, $id, from database.\n";
    }
    return $analysis;
}

=method fetch_by_ids

  Usage       : $analyses = $analysis_adaptor->fetch_by_ids( \@analysis_ids );
  Purpose     : Fetch a list of analyses given a list of db ids
  Returns     : Arrayref of Crispr::DB::Analysis objects
  Parameters  : Arrayref of crispr-db analysis ids
  Throws      : If no rows are returned from the database for one of ids
                If too many rows are returned from the database for one of ids
  Comments    : None

=cut

sub fetch_by_ids {
    my ( $self, $ids ) = @_;
	my @analyses;
    foreach my $id ( @{$ids} ){
        push @analyses, $self->fetch_by_id( $id );
    }
	
    return \@analyses;
}

=method fetch_all_by_plex_id

  Usage       : $analyses = $analysis_adaptor->fetch_all_by_plex_id( $plex_id );
  Purpose     : Fetch an analysis given a plex database id
  Returns     : Crispr::DB::Analysis object
  Parameters  : Int
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_plex_id {
    my ( $self, $plex_id ) = @_;
    my $analyses = $self->_fetch( 'plex_id = ?;', [ $plex_id ] );
    if( !$analyses ){
        confess join(q{ }, "Couldn't retrieve analyses for plex id, ",
                     $plex_id, "from database.\n" );
    }
    return $analyses;
}

=method fetch_all_by_plex

  Usage       : $analyses = $analysis_adaptor->fetch_all_by_plex( $plex );
  Purpose     : Fetch an analysis given a Plex object
  Returns     : Crispr::DB::Analysis object
  Parameters  : Crispr::DB::Plex object
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_plex {
    my ( $self, $plex ) = @_;
    return $self->fetch_all_by_plex_id( $plex->db_id );
}

#_fetch
#
#Usage       : $analysis = $self->_fetch( \@fields );
#Purpose     : Fetch a Analysis object from the database with arbitrary parameteres
#Returns     : ArrayRef of Crispr::DB::Analysis objects
#Parameters  : where_clause => Str (SQL where clause)
#               where_parameters => ArrayRef of parameters to bind to sql statement
#Throws      : 
#Comments    : 

sub _fetch {
    my ( $self, $where_clause, $where_parameters ) = @_;
    my $dbh = $self->connection->dbh();
    
    my $sql = <<'END_SQL';
        SELECT
            analysis_id, plex_id,
            analysis_started, analysis_finished
        FROM analysis
END_SQL

    if ($where_clause) {
        $sql .= 'WHERE ' . $where_clause;
    }
    
    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $analysis_id, $plex_id,
            $analysis_started, $analysis_finished, );
    
    $sth->bind_columns( \( $analysis_id, $plex_id,
            $analysis_started, $analysis_finished, ) );

    my @analyses = ();
    while ( $sth->fetch ) {
        
        my $analysis;
        if( !exists $self->_analysis_cache->{ $analysis_id } ){
            # fetch plex by plex_id
            my $plex = $self->plex_adaptor->fetch_by_id( $plex_id );
            my $sample_amplicons = $self->sample_amplicon_adaptor->fetch_all_by_analysis_id( $analysis_id );
            
            $analysis = Crispr::DB::Analysis->new(
                db_id => $analysis_id,
                plex => $plex,
                analysis_started => $analysis_started,
                analysis_finished => $analysis_finished,
                info => $sample_amplicons,
            );
            my $analysis_cache = $self->_analysis_cache;
            $analysis_cache->{ $analysis_id } = $analysis;
            $self->_set_analysis_cache( $analysis_cache );
        }
        else{
            $analysis = $self->_analysis_cache->{ $analysis_id };
        }
        
        push @analyses, $analysis;
    }

    return \@analyses;    
}

=method delete_analysis_from_db

  Usage       : $analysis_adaptor->delete_analysis_from_db( $analysis );
  Purpose     : Delete a analysis from the database
  Returns     : Crispr::DB::Analysis object
  Parameters  : Crispr::DB::Analysis object
  Throws      : 
  Comments    : Not implemented yet.

=cut

sub delete_analysis_from_db {
	#my ( $self, $analysis ) = @_;
	
	# first check analysis exists in db
	
	# delete primers and primer pairs
	
	# delete transcripts
	
	# if analysis has talen pairs, delete tale and talen pairs

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
 
    use Crispr::DB::DBAdaptor;
    my $db_adaptor = Crispr::DB::DBAdaptor->new(
        host => 'HOST',
        port => 'PORT',
        dbname => 'DATABASE',
        user => 'USER',
        pass => 'PASS',
        connection => $dbc,
    );
  
    my $analysis_adaptor = $db_adaptor->get_adaptor( 'analysis' );
    
    # store a analysis object in the db
    $analysis_adaptor->store( $analysis );
    
    # retrieve a analysis by id
    my $analysis = $analysis_adaptor->fetch_by_id( '214' );
  
    # retrieve a list of analyses by date
    my $analyses = $analysis_adaptor->fetch_by_date( '2015-04-27' );
    

=head1 DESCRIPTION
 
 A AnalysisAdaptor is an object used for storing and retrieving Analysis objects in an SQL database.
 The recommended way to use this module is through the DBAdaptor object as shown above.
 This allows a single open connection to the database which can be shared between multiple database adaptors.
 
=head1 DIAGNOSTICS
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
=head1 DEPENDENCIES
 
 
=head1 INCOMPATIBILITIES
 
