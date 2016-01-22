## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::SampleAdaptor;
## use critic

# ABSTRACT: SampleAdaptor object - object for storing Sample objects in and retrieving them from a SQL database

use namespace::autoclean;
use Moose;
use DateTime;
use Carp qw( cluck confess );
use English qw( -no_match_vars );
use List::MoreUtils qw( any );
use Crispr::DB::Sample;
use Labware::Well;
use Data::Dumper;

extends 'Crispr::DB::BaseAdaptor';

my %sample_cache; # Cache for Sample objects. HashRef keyed on sample_id (db_id)

=method new

  Usage       : my $sample_adaptor = Crispr::DB::SampleAdaptor->new(
					db_connection => $db_connection,
                );
  Purpose     : Constructor for creating sample adaptor objects
  Returns     : Crispr::DB::SampleAdaptor object
  Parameters  :     db_connection => Crispr::DB::DBConnection object,
  Throws      : If parameters are not the correct type
  Comments    : The preferred method for constructing a SampleAdaptor is to use the
                get_adaptor method with a previously constructed DBConnection object

=cut

=method analysis_adaptor

  Usage       : $self->analysis_adaptor();
  Purpose     : Getter for a analysis_adaptor.
  Returns     : Crispr::DB::AnalysisAdaptor
  Parameters  : None
  Throws      :
  Comments    :

=cut

has 'analysis_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::AnalysisAdaptor',
    lazy => 1,
    builder => '_build_analysis_adaptor',
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

=method allele_adaptor

  Usage       : $self->allele_adaptor();
  Purpose     : Getter for a allele_adaptor.
  Returns     : Crispr::DB::AlleleAdaptor
  Parameters  : None
  Throws      :
  Comments    :

=cut

has 'allele_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::AlleleAdaptor',
    lazy => 1,
    builder => '_build_allele_adaptor',
);

=method store

  Usage       : $sample = $sample_adaptor->store( $sample );
  Purpose     : Store a sample in the database
  Returns     : Crispr::DB::Sample object
  Parameters  : Crispr::DB::Sample object
  Throws      : If argument is not a Sample object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    :

=cut

sub store {
    my ( $self, $sample, ) = @_;
	# make an arrayref with this one sample and call store_samples
	my @samples = ( $sample );
	my $samples = $self->store_samples( \@samples );

	return $samples->[0];
}

=method store_sample

  Usage       : $sample = $sample_adaptor->store_sample( $sample );
  Purpose     : Store a sample in the database
  Returns     : Crispr::DB::Sample object
  Parameters  : Crispr::DB::Sample object
  Throws      : If argument is not a Sample object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : Synonym for store

=cut

sub store_sample {
    my ( $self, $sample, ) = @_;
	return $self->store( $sample );
}

=method store_samples

  Usage       : $samples = $sample_adaptor->store_samples( $samples );
  Purpose     : Store a set of samples in the database
  Returns     : ArrayRef of Crispr::DB::Sample objects
  Parameters  : ArrayRef of Crispr::DB::Sample objects
  Throws      : If argument is not an ArrayRef
                If objects in ArrayRef are not Crispr::DB::Sample objects
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None

=cut

sub store_samples {
    my ( $self, $samples, ) = @_;
    my $dbh = $self->connection->dbh();

	confess "Supplied argument must be an ArrayRef of Sample objects.\n" if( ref $samples ne 'ARRAY');
	foreach my $sample ( @{$samples} ){
        if( !ref $sample ){
            confess "Argument must be Crispr::DB::Sample objects.\n";
        }
        elsif( !$sample->isa('Crispr::DB::Sample') ){
            confess "Argument must be Crispr::DB::Sample objects.\n";
        }
    }

    my $add_sample_statement = "insert into sample values( ?, ?, ?, ?, ?, ?, ?, ?, ? );";

    $self->connection->txn(  fixup => sub {
        my $sth = $dbh->prepare($add_sample_statement);
        foreach my $sample ( @{$samples} ){
            # check injection pool for id and check it exists in the db
            my ( $inj_pool_check_statement, $inj_pool_params );
            if( !defined $sample->injection_pool ){
                confess join("\n", "One of the Sample objects does not contain an InjectionPool object.",
                    "This is required to able to add the sample to the database.", ), "\n";
            }
            else{
                if( defined $sample->injection_pool->db_id ){
                    $inj_pool_check_statement = "SELECT count(*) FROM injection WHERE injection_id = ?;";
                    $inj_pool_params = [ $sample->injection_pool->db_id ];
                }
                elsif( defined $sample->injection_pool->pool_name ){
                    $inj_pool_check_statement = "SELECT count(*) FROM injection i WHERE injection_name = ?;";
                    $inj_pool_params = [ $sample->injection_pool->pool_name ];
                }
                else{
                    confess join("\n", "One of the Sample objects contains an InjectionPool object with neither a db_id nor an injection_name.",
                        "This is required to able to add the sample to the database.", ), "\n";
                }
            }
            # check injection_pool exists in db
            if( !$self->check_entry_exists_in_db( $inj_pool_check_statement, $inj_pool_params ) ){
                # try storing it
                my $injection_pool = $self->injection_pool_adaptor->store( $sample->injection_pool );
                $sample->injection_pool->db_id( $injection_pool->db_id )
            }
            # need db_id
            my $injection_id;
            if( defined $sample->injection_pool->db_id ){
                $injection_id = $sample->injection_pool->db_id;
            }
            else{
                my $injection_pool = $self->injection_pool_adaptor->fetch_by_name( $sample->injection_pool->pool_name );
                $injection_id = $injection_pool->db_id;
            }

            my $well_id = defined $sample->well ? $sample->well->position : undef;
            # add sample
            $sth->execute(
                $sample->db_id, $sample->sample_name, $sample->sample_number,
                $injection_id, $sample->generation, $sample->sample_type,
                $sample->species, $well_id, $sample->cryo_box,
            );

            my $last_id;
            $last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'sample', 'sample_id' );
            $sample->db_id( $last_id );
        }
        $sth->finish();
    } );

    return $samples;
}

=method store_alleles_for_sample

  Usage       : $samples = $sample_adaptor->store_alleles_for_sample( $sample );
  Purpose     : Store a set of samples in the database
  Returns     : ArrayRef of Crispr::DB::Sample objects
  Parameters  : ArrayRef of Crispr::DB::Sample objects
  Throws      : If argument is not an ArrayRef
                If objects in ArrayRef are not Crispr::DB::Sample objects
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None

=cut

sub store_alleles_for_sample {
    my ( $self, $sample, ) = @_;
    my $dbh = $self->connection->dbh();

    if( !defined $sample ){
        die "store_alleles_for_sample: UNDEFINED SAMPLE";
    }
    elsif( !defined $sample->alleles ){
        die "store_alleles_for_sample: UNDEFINED ALLELES";
    }
    my $add_allele_statement = "insert into sample_allele values( ?, ?, ? );";

    # start transaction
    $self->connection->txn(  fixup => sub {
        my $sth = $dbh->prepare($add_allele_statement);
        # go through alleles
        foreach my $allele ( @{ $sample->alleles } ){
            # check that it exists in the db
            my ( $allele_check_statement, $allele_params );
            if( defined $allele->db_id ){
                $allele_check_statement = "SELECT count(*) FROM allele WHERE allele_id = ?;";
                $allele_params = [ $allele->db_id ];
            }
            elsif( defined $allele->allele_number ){
                $allele_check_statement = "SELECT count(*) FROM allele WHERE allele_number = ?;";
                $allele_params = [ $allele->allele_number ];
            }
            else{
                die join("\n", "store_alleles_for_sample: The Sample contains an Allele object with neither a db_id nor an allele_number.",
                    "This is required to able to add the allele to the database.", ), "\n";
            }
            # check allele exists in db
            if( !$self->check_entry_exists_in_db( $allele_check_statement, $allele_params ) ){
                # try storing it
                my $allele = $self->allele_adaptor->store( $allele );
            }
            else{
                if( !defined $allele->db_id ){
                    # get id from db
                    $allele = $self->allele_adaptor->fetch_by_allele_number( $allele->allele_number )
                }
            }

            # add sample and allele ids to sample_allele table
            $sth->execute(
                $sample->db_id,
                $allele->db_id,
                $allele->percent_of_reads,
            );
        }

        $sth->finish();
    } );
}

sub store_sequencing_results {
    my ( $self, $sample, $sequencing_results ) = @_;
    my $dbh = $self->connection->dbh();
    #
    my $add_seq_statement = 'insert into sequencing_results values( ?, ?, ?, ?, ?, ?, ? )';
    $self->connection->txn(  fixup => sub {
        my $sth = $dbh->prepare($add_seq_statement);
        foreach my $crRNA_id ( keys %{$sequencing_results} ){
            my $results = $sequencing_results->{$crRNA_id};
            $sth->execute(
                $sample->db_id, $crRNA_id,
                $results->{'fail'},
                $results->{'num_indels'},
                $results->{'total_percentage'},
                $results->{'percentage_major_variant'},
                $sample->total_reads,
            );
        }
        $sth->finish();
    } );
}

=method fetch_by_id

  Usage       : $samples = $sample_adaptor->fetch_by_id( $sample_id );
  Purpose     : Fetch a sample given its database id
  Returns     : Crispr::DB::Sample object
  Parameters  : crispr-db sample_id - Int
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_by_id {
    my ( $self, $id ) = @_;
    my $sample;
    if( exists $sample_cache{$id} ){
        $sample = $sample_cache{$id};
    }
    else{
        $sample = $self->_fetch( 'sample_id = ?;', [ $id ] )->[0];
        if( !$sample ){
            confess "Couldn't retrieve sample, $id, from database.\n";
        }
    }
    return $sample;
}

=method fetch_by_ids

  Usage       : $samples = $sample_adaptor->fetch_by_ids( \@sample_ids );
  Purpose     : Fetch a list of samples given a list of db ids
  Returns     : Arrayref of Crispr::DB::Sample objects
  Parameters  : Arrayref of crispr-db sample ids
  Throws      : If no rows are returned from the database for one of ids
                If too many rows are returned from the database for one of ids
  Comments    : None

=cut

sub fetch_by_ids {
    my ( $self, $ids ) = @_;
	my @samples;
    foreach my $id ( @{$ids} ){
        push @samples, $self->fetch_by_id( $id );
    }

    return \@samples;
}

=method fetch_by_name

  Usage       : $samples = $sample_adaptor->fetch_by_name( $sample_name );
  Purpose     : Fetch a sample given its database name
  Returns     : Crispr::DB::Sample object
  Parameters  : crispr-db sample_name - Str
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_by_name {
    my ( $self, $name ) = @_;
    my $sample = $self->_fetch( 'sample_name = ?;', [ $name ] )->[0];
    if( !$sample ){
        confess "Couldn't retrieve sample, $name, from database.\n";
    }
    return $sample;
}

=method fetch_all_by_injection_id

  Usage       : $samples = $sample_adaptor->fetch_all_by_injection_id( $inj_id );
  Purpose     : Fetch a sample given an InjectionPool db_id
  Returns     : ArrayRef of Crispr::DB::Sample objects
  Parameters  : Crispr::DB::InjectionPool object
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_injection_id {
    my ( $self, $inj_id ) = @_;
    my $samples = $self->_fetch( 'injection_id = ?;', [ $inj_id ] );
    if( ! @{$samples} ){
        confess join(q{ }, "Couldn't retrieve samples for injection id,",
                     $inj_id, "from database.\n" );
    }
    return $samples;
}

=method fetch_all_by_injection_pool

  Usage       : $samples = $sample_adaptor->fetch_all_by_injection_pool( $inj_pool );
  Purpose     : Fetch a sample given an InjectionPool object
  Returns     : ArrayRef of Crispr::DB::Sample objects
  Parameters  : Crispr::DB::InjectionPool object
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_injection_pool {
    my ( $self, $inj_pool ) = @_;
    return $self->fetch_all_by_injection_id( $inj_pool->db_id );
}

=method fetch_all_by_analysis_id

  Usage       : $samples = $sample_adaptor->fetch_all_by_plex_id( $plex_id );
  Purpose     : Fetch an sample given a plex database id
  Returns     : Crispr::DB::Sample object
  Parameters  : Int
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_analysis_id {
    my ( $self, $analysis_id ) = @_;

    my $where_clause = 'analysis_id = ?;';
    my $where_parameters = [ $analysis_id ];
    my $sql = <<'END_SQL';
        SELECT
            s.sample_id, sample_name, sample_number,
            injection_id, generation, type, species,
            s.well_id, cryo_box
        FROM sample s, analysis_information info
        WHERE s.sample_id = info.sample_id
END_SQL

    $sql .= 'AND ' . $where_clause;

    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $sample_id, $sample_name, $sample_number, $injection_id,
        $generation, $type, $species, $well_id, $cryo_box, );

    $sth->bind_columns( \( $sample_id, $sample_name, $sample_number,
                          $injection_id, $generation, $type, $species,
                          $well_id, $cryo_box, ) );

    my @samples = ();
    while ( $sth->fetch ) {

        my $sample;
        if( !exists $sample_cache{ $sample_id } ){
            # fetch injection pool by id
            my $injection_pool = $self->injection_pool_adaptor->fetch_by_id( $injection_id );

            my $well = defined $well_id ?
                Labware::Well->new( position => $well_id )
                :   undef;
            $sample = Crispr::DB::Sample->new(
                db_id => $sample_id,
                sample_name => $sample_name,
                sample_number => $sample_number,
                injection_pool => $injection_pool,
                generation => $generation,
                sample_type => $type,
                species => $species,
                well => $well,
                cryo_box => $cryo_box,
            );
            $sample_cache{ $sample_id } = $sample;
        }
        else{
            $sample = $sample_cache{ $sample_id };
        }

        push @samples, $sample;
    }

    if( ! @samples ){
        confess join(q{ }, "Couldn't retrieve samples for analysis id,",
                     $analysis_id, "from database.\n" );
    }

    return \@samples;
}

=method fetch_all_by_analysis

  Usage       : $samples = $sample_adaptor->fetch_all_by_analysis( $analysis );
  Purpose     : Fetch an sample given a Analysis object
  Returns     : Crispr::DB::Sample object
  Parameters  : Crispr::DB::Analysis object
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_analysis {
    my ( $self, $analysis ) = @_;
    # check whether it an Analysis object
    if( !ref $analysis ){
        confess "Argument must be a Crispr::DB::Analysis object.\n";
    }
    elsif( !$analysis->isa('Crispr::DB::Analysis') ){
        confess "Argument must be a Crispr::DB::Analysis object.\n";
    }
    return $self->fetch_all_by_analysis_id( $analysis->db_id );
}

#_fetch
#
#Usage       : $sample = $self->_fetch( \@fields );
#Purpose     : Fetch a Sample object from the database with arbitrary parameteres
#Returns     : ArrayRef of Crispr::DB::Sample objects
#Parameters  : where_clause => Str (SQL where clause)
#               where_parameters => ArrayRef of parameters to bind to sql statement
#Throws      :
#Comments    :

sub _fetch {
    my ( $self, $where_clause, $where_parameters ) = @_;
    my $dbh = $self->connection->dbh();

    my $sql = <<'END_SQL';
        SELECT
            sample_id, sample_name, sample_number,
            injection_id, generation, type, species,
            well_id, cryo_box
        FROM sample
END_SQL

    if ($where_clause) {
        $sql .= 'WHERE ' . $where_clause;
    }

    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $sample_id, $sample_name, $sample_number, $injection_id,
        $generation, $type, $species, $well_id, $cryo_box, );

    $sth->bind_columns( \( $sample_id, $sample_name, $sample_number,
                          $injection_id, $generation, $type, $species,
                          $well_id, $cryo_box, ) );

    my @samples = ();
    while ( $sth->fetch ) {

        my $sample;
        if( !exists $sample_cache{ $sample_id } ){
            # fetch injection pool by id
            my $injection_pool = $self->injection_pool_adaptor->fetch_by_id( $injection_id );

            my $well = defined $well_id ?
                Labware::Well->new( position => $well_id )
                :   undef;
            $sample = Crispr::DB::Sample->new(
                db_id => $sample_id,
                sample_name => $sample_name,
                sample_number => $sample_number,
                injection_pool => $injection_pool,
                generation => $generation,
                sample_type => $type,
                species => $species,
                well => $well,
                cryo_box => $cryo_box,
            );
            $sample_cache{ $sample_id } = $sample;
        }
        else{
            $sample = $sample_cache{ $sample_id };
        }

        push @samples, $sample;
    }

    return \@samples;
}

=method delete_sample_from_db

  Usage       : $sample_adaptor->delete_sample_from_db( $sample );
  Purpose     : Delete a sample from the database
  Returns     : Crispr::DB::Sample object
  Parameters  : Crispr::DB::Sample object
  Throws      :
  Comments    : Not inmplemented yet.

=cut

sub delete_sample_from_db {
	#my ( $self, $sample ) = @_;

	# first check sample exists in db

	# delete primers and primer pairs

	# delete transcripts

	# if sample has talen pairs, delete tale and talen pairs

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

    my $sample_adaptor = $db_adaptor->get_adaptor( 'sample' );

    # store a sample object in the db
    $sample_adaptor->store( $sample );

    # retrieve a sample by id
    my $sample = $sample_adaptor->fetch_by_id( '214' );

    # retrieve a list of samples by date
    my $samples = $sample_adaptor->fetch_by_date( '2015-04-27' );


=head1 DESCRIPTION

 A SampleAdaptor is an object used for storing and retrieving Sample objects in an SQL database.
 The recommended way to use this module is through the DBAdaptor object as shown above.
 This allows a single open connection to the database which can be shared between multiple database adaptors.

=head1 DIAGNOSTICS


=head1 CONFIGURATION AND ENVIRONMENT


=head1 DEPENDENCIES


=head1 INCOMPATIBILITIES
