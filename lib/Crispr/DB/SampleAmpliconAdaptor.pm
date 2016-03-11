## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::SampleAmpliconAdaptor;

## use critic

# ABSTRACT: SampleAmpliconAdaptor object - object for storing SampleAmplicon objects in and retrieving them from a SQL database

use namespace::autoclean;
use Moose;
use DateTime;
use Carp qw( cluck confess );
use English qw( -no_match_vars );
use List::MoreUtils qw( any );
use Crispr::DB::SampleAmplicon;

extends 'Crispr::DB::BaseAdaptor';

=method new

  Usage       : my $sample_amplicon_adaptor = Crispr::DB::SampleAmpliconAdaptor->new(
					db_connection => $db_connection,
                );
  Purpose     : Constructor for creating sample_amplicon adaptor objects
  Returns     : Crispr::DB::SampleAmpliconAdaptor object
  Parameters  :     db_connection => Crispr::DB::DBConnection object,
  Throws      : If parameters are not the correct type
  Comments    : The preferred method for constructing a SampleAmpliconAdaptor is to use the
                get_adaptor method with a previously constructed DBConnection object

=cut

=method store

  Usage       : $sample_amplicon = $sample_amplicon_adaptor->store( $sample_amplicon );
  Purpose     : Store a sample_amplicon in the database
  Returns     : Crispr::DB::SampleAmplicon object
  Parameters  : Crispr::DB::SampleAmplicon object
  Throws      : If argument is not a SampleAmplicon object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : 

=cut

sub store {
    my ( $self, $sample_amplicon, ) = @_;
	# make an arrayref with this one sample_amplicon and call store_sample_amplicons
	my @sample_amplicons = ( $sample_amplicon );
	my $sample_amplicons = $self->store_sample_amplicons( \@sample_amplicons );
	
	return $sample_amplicons->[0];
}

=method store_sample_amplicon

  Usage       : $sample_amplicon = $sample_amplicon_adaptor->store_sample_amplicon( $sample_amplicon );
  Purpose     : Store a sample_amplicon in the database
  Returns     : Crispr::DB::SampleAmplicon object
  Parameters  : Crispr::DB::SampleAmplicon object
  Throws      : If argument is not a SampleAmplicon object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : Synonym for store

=cut

sub store_sample_amplicon {
    my ( $self, $sample_amplicon, ) = @_;
	return $self->store( $sample_amplicon );
}

=method store_sample_amplicons

  Usage       : $sample_amplicons = $sample_amplicon_adaptor->store_sample_amplicons( $sample_amplicons );
  Purpose     : Store a set of sample_amplicons in the database
  Returns     : ArrayRef of Crispr::DB::SampleAmplicon objects
  Parameters  : ArrayRef of Crispr::DB::SampleAmplicon objects
  Throws      : If argument is not an ArrayRef
                If objects in ArrayRef are not Crispr::DB::SampleAmplicon objects
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None
   
=cut

sub store_sample_amplicons {
    my ( $self, $sample_amplicons, ) = @_;
    my $dbh = $self->connection->dbh();
    
	confess "Supplied argument must be an ArrayRef of SampleAmplicon objects.\n" if( ref $sample_amplicons ne 'ARRAY');
	foreach my $sample_amplicon ( @{$sample_amplicons} ){
        if( !ref $sample_amplicon || !$sample_amplicon->isa('Crispr::DB::SampleAmplicon') ){
            confess "Argument must be a Crispr::DB::SampleAmplicon object.\n";
        }
    }
    
    my $add_sample_amplicon_statement = "insert into analysis_information values( ?, ?, ?, ?, ?, ? );"; 
    
    $self->connection->txn(  fixup => sub {
        my $sth = $dbh->prepare($add_sample_amplicon_statement);
        foreach my $sample_amplicon ( @{$sample_amplicons} ){
            # check analysis_id is set and whether analysis exists in db
            if( !defined $sample_amplicon->analysis_id ){
                    confess join("\n", "One of the SampleAmplicon objects does not contain an analysis_id.",
                        "This is required to able to add the sample_amplicon to the database.", ), "\n";
            }
            else{
                my $analysis_check_statement = 'select count(*) from analysis where analysis_id = ?;';
                if( !$self->check_entry_exists_in_db( $analysis_check_statement,
                        [ $sample_amplicon->analysis_id ] ) ){
                    # complain
                    die "Analysis with id: ", $sample_amplicon->analysis_id,
                        "does not exist in the database yet!\n",
                        "Sample-Amplicon information cannot be added until the analysis is in the database.\n";
                }
            }
            
            # check samples exist in the db
            my $sample;
            if( !defined $sample_amplicon->sample ){
                    confess join("\n", "One of the SampleAmplicon objects does not contain a Sample object.",
                        "This is required to able to add the sample_amplicon to the database.", ), "\n";
            }
            else{
                $sample = $sample_amplicon->sample;
                my ( $sample_check_statement, $sample_params );
                
                if( defined $sample->db_id ){
                    $sample_check_statement = "select count(*) from sample where sample_id = ?;";
                    $sample_params = [ $sample->db_id ];
                }
                elsif( defined $sample->sample_name ){
                    $sample_check_statement = "select count(*) from sample where sample_name = ?;";
                    $sample_params = [ $sample->sample_name ];
                }
                # check sample_pool exists in db
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
            
            # check primer_pairs exist in the db
            if( !defined $sample_amplicon->amplicons ){
                    confess join("\n", "One of the SampleAmplicon objects does not contain any PrimerPair objects.",
                        "This is required to able to add the sample_amplicon to the database.", ), "\n";
            }
            else{
                foreach my $primer_pair ( @{ $sample_amplicon->amplicons } ){
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
            
            foreach my $primer_pair ( @{ $sample_amplicon->amplicons } ){
                # add to sample_amplicon info table
                $sth->execute(
                    $sample_amplicon->analysis_id,
                    $sample->db_id,
                    $primer_pair->primer_pair_id, 
                    $sample_amplicon->barcode_id,
                    $sample_amplicon->plate_number,
                    $sample_amplicon->well_id,
                );
                
            }
        }
        $sth->finish();
    } );
    
    return $sample_amplicons;
}

=method fetch_all_by_analysis_id

  Usage       : $sample_amplicons = $sample_amplicon_adaptor->fetch_all_by_analysis_id( $analysis_id );
  Purpose     : Fetch an sample_amplicon given a analysis database id
  Returns     : Crispr::DB::SampleAmplicon object
  Parameters  : Int
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_analysis_id {
    my ( $self, $analysis_id ) = @_;
    my $sample_amplicons = $self->_fetch( 'analysis_id = ?;', [ $analysis_id ] );
    if( !$sample_amplicons ){
        confess join(q{ }, "Couldn't retrieve sample_amplicons for analysis id, ",
                     $analysis_id, "from database.\n" );
    }
    return $sample_amplicons;
}

=method fetch_all_by_analysis

  Usage       : $sample_amplicons = $sample_amplicon_adaptor->fetch_all_by_analysis( $analysis );
  Purpose     : Fetch an sample_amplicon given a Plex object
  Returns     : Crispr::DB::SampleAmplicon object
  Parameters  : Crispr::DB::Plex object
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_analysis {
    my ( $self, $analysis ) = @_;
    return $self->fetch_all_by_analysis_id( $analysis->db_id );
}

#=method fetch_all_by_injection_id
#
#  Usage       : $sample_amplicons = $sample_amplicon_adaptor->fetch_all_by_injection_id( $inj_id );
#  Purpose     : Fetch an sample_amplicon given an InjectionPool object
#  Returns     : Crispr::DB::SampleAmplicon object
#  Parameters  : Crispr::DB::InjectionPool object
#  Throws      : If no rows are returned from the database or if too many rows are returned
#  Comments    : None
#
#=cut
#
#sub fetch_all_by_injection_id {
#    my ( $self, $inj_id ) = @_;
#    my $sample_amplicons = $self->_fetch( 'injection_id = ?;', [ $inj_id ] );
#    if( !$sample_amplicons ){
#        confess join(q{ }, "Couldn't retrieve sample_amplicons for injection id,",
#                     $inj_id, "from database.\n" );
#    }
#    return $sample_amplicons;
#}
#
#=method fetch_all_by_injection_pool
#
#  Usage       : $sample_amplicons = $sample_amplicon_adaptor->fetch_all_by_injection_pool( $inj_pool );
#  Purpose     : Fetch an sample_amplicon given an InjectionPool object
#  Returns     : Crispr::DB::SampleAmplicon object
#  Parameters  : Crispr::DB::InjectionPool object
#  Throws      : If no rows are returned from the database or if too many rows are returned
#  Comments    : None
#
#=cut
#
#sub fetch_all_by_injection_pool {
#    my ( $self, $inj_pool ) = @_;
#    return $self->fetch_all_by_injection_id( $inj_pool->db_id );
#}

#_fetch
#
#Usage       : $sample_amplicon = $self->_fetch( \@fields );
#Purpose     : Fetch a SampleAmplicon object from the database with arbitrary parameteres
#Returns     : ArrayRef of Crispr::DB::SampleAmplicon objects
#Parameters  : where_clause => Str (SQL where clause)
#               where_parameters => ArrayRef of parameters to bind to sql statement
#Throws      : 
#Comments    : 

my %sample_amplicon_cache; # Cache for SampleAmplicon objects. HashRef keyed on analysis_id.sample_id
sub _fetch {
    my ( $self, $where_clause, $where_parameters ) = @_;
    my $dbh = $self->connection->dbh();
    
    my $sql = <<'END_SQL';
        SELECT
            analysis_id, sample_id, primer_pair_id,
            barcode_id, plate_number, well_id
        FROM analysis_information
END_SQL

    if ($where_clause) {
        $sql .= 'WHERE ' . $where_clause;
    }
    
    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $analysis_id, $sample_id, $primer_pair_id,
            $barcode_id, $plate_number, $well_id );
    
    $sth->bind_columns( \( $analysis_id, $sample_id, $primer_pair_id,
            $barcode_id, $plate_number, $well_id ) );
    
    my %samples_amplicons_for = ();
    while ( $sth->fetch ) {
        # fetch sample by sample id
        my $sample = $self->sample_adaptor->fetch_by_id( $sample_id );
        # fetch primer
        my $primer_pair = $self->primer_pair_adaptor->fetch_by_id( $primer_pair_id );
        
        $samples_amplicons_for{ $sample->sample_name }{ 'sample' } = $sample;
        push @{ $samples_amplicons_for{ $sample->sample_name }{ 'amplicons' } }, $primer_pair;
        $samples_amplicons_for{ $sample->sample_name }{ 'analysis_id' } = $analysis_id;
        $samples_amplicons_for{ $sample->sample_name }{ 'barcode_id' } = $barcode_id;
        $samples_amplicons_for{ $sample->sample_name }{ 'plate_number' } = $plate_number;
        $samples_amplicons_for{ $sample->sample_name }{ 'well_id' } = $well_id;
    }
    
    my @sample_amplicons;
    foreach my $sample_name ( sort keys %samples_amplicons_for ){
        my $sample_amplicon;
        my $args = $samples_amplicons_for{ $sample_name };
        my $sample_amplicon_id =
            join(q{.}, $samples_amplicons_for{ $sample_name }{ 'sample' }->db_id,
                $samples_amplicons_for{ $sample_name }{ 'analysis_id' } );
        if( !exists $sample_amplicon_cache{ $sample_amplicon_id } ){
            
            $sample_amplicon = Crispr::DB::SampleAmplicon->new( $args );
            $sample_amplicon_cache{ $sample_amplicon_id } = $sample_amplicon;
        }
        else{
            $sample_amplicon = $sample_amplicon_cache{ $sample_amplicon_id };
        }
        
        push @sample_amplicons, $sample_amplicon;
    }

    return \@sample_amplicons;    
}

=method delete_sample_amplicon_from_db

  Usage       : $sample_amplicon_adaptor->delete_sample_amplicon_from_db( $sample_amplicon );
  Purpose     : Delete a sample_amplicon from the database
  Returns     : Crispr::DB::SampleAmplicon object
  Parameters  : Crispr::DB::SampleAmplicon object
  Throws      : 
  Comments    : Not implemented yet.

=cut

sub delete_sample_amplicon_from_db {
	#my ( $self, $sample_amplicon ) = @_;
	
	# first check sample_amplicon exists in db
	
	# delete primers and primer pairs
	
	# delete transcripts
	
	# if sample_amplicon has talen pairs, delete tale and talen pairs

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
  
    my $sample_amplicon_adaptor = $db_adaptor->get_adaptor( 'sample_amplicon' );
    
    # store a sample_amplicon object in the db
    $sample_amplicon_adaptor->store( $sample_amplicon );
    
    # retrieve a sample_amplicon by id
    my $sample_amplicon = $sample_amplicon_adaptor->fetch_by_id( '214' );
  
    # retrieve a list of sample_amplicons by date
    my $sample_amplicons = $sample_amplicon_adaptor->fetch_by_date( '2015-04-27' );
    

=head1 DESCRIPTION
 
 A SampleAmpliconAdaptor is an object used for storing and retrieving SampleAmplicon objects in an SQL database.
 The recommended way to use this module is through the DBAdaptor object as shown above.
 This allows a single open connection to the database which can be shared between multiple database adaptors.
 
=head1 DIAGNOSTICS
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
=head1 DEPENDENCIES
 
 
=head1 INCOMPATIBILITIES
 
