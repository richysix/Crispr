## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::SampleAlleleAdaptor;

## use critic

# ABSTRACT: SampleAlleleAdaptor object - object for storing SampleAllele objects in and retrieving them from an SQL database

use namespace::autoclean;
use Moose;
use DateTime;
use Carp qw( cluck confess );
use English qw( -no_match_vars );
use Crispr::DB::SampleAllele;

extends 'Crispr::DB::BaseAdaptor';

=method new

  Usage       : my $sample_allele_adaptor = Crispr::DB::SampleAlleleAdaptor->new(
                    db_connection => $db_connection,
                );
  Purpose     : Constructor for creating sample_allele adaptor objects
  Returns     : Crispr::DB::SampleAlleleAdaptor object
  Parameters  :     db_connection => Crispr::DB::DBConnection object,
  Throws      : If parameters are not the correct type
  Comments    : The preferred method for constructing a SampleAlleleAdaptor is to use the
                get_adaptor method with a previously constructed DBConnection object

=cut

# cache for sample_allele objects from db
has '_sample_allele_cache' => (
	is => 'ro',
	isa => 'HashRef',
    init_arg => undef,
    writer => '_set_sample_allele_cache',
    default => sub { return {}; },
);

=method store

  Usage       : $sample_allele = $sample_allele_adaptor->store( $sample_allele );
  Purpose     : Store a sample_allele object in the database
  Returns     : Crispr::SampleAllele object
  Parameters  : Crispr::SampleAllele object
  Throws      : If argument is not a SampleAllele object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    :

=cut

sub store {
    my ( $self, $sample_allele, ) = @_;
    # make an arrayref with this one sample_allele and call store_sample_alleles
    my @sample_alleles = ( $sample_allele );
    my $sample_alleles = $self->store_sample_alleles( \@sample_alleles );

    return $sample_alleles->[0];
}

=method store_sample_allele

  Usage       : $sample_allele = $sample_allele_adaptor->store_sample_allele( $sample_allele );
  Purpose     : Store a sample_allele in the database
  Returns     : Crispr::SampleAllele object
  Parameters  : Crispr::SampleAllele object
  Throws      : If argument is not a SampleAllele object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : Synonym for store

=cut

sub store_sample_allele {
    my ( $self, $sample_allele, ) = @_;
    return $self->store( $sample_allele );
}

=method store_sample_alleles

  Usage       : $sample_alleles = $sample_allele_adaptor->store_sample_alleles( $sample_alleles );
  Purpose     : Store a set of sample_alleles in the database
  Returns     : ArrayRef of Crispr::SampleAllele objects
  Parameters  : ArrayRef of Crispr::SampleAllele objects
  Throws      : If argument is not an ArrayRef
                If objects in ArrayRef are not Crispr::SampleAllele objects
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None

=cut

sub store_sample_alleles {
    my ( $self, $sample_alleles, ) = @_;
    my $dbh = $self->connection->dbh();

    confess "Supplied argument must be an ArrayRef of SampleAllele objects.\n" if( ref $sample_alleles ne 'ARRAY');
    foreach ( @{$sample_alleles} ){
        if( !ref $_ || !$_->isa('Crispr::DB::SampleAllele') ){
            confess "Argument must be Crispr::DB::SampleAllele objects.\n";
        }
    }

    my $add_sample_allele_statement = "insert into sample_allele values( ?, ?, ? );";

    # start transaction
    $self->connection->txn(  fixup => sub {
        my $sth = $dbh->prepare($add_sample_allele_statement);
        # go through alleles
        foreach my $sample_allele ( @{ $sample_alleles } ){
            my $allele = $sample_allele->allele;
            my $sample = $sample_allele->sample;
            # check allele exists in db
            if( !$self->allele_adaptor->allele_exists_in_db( $allele, ) ){
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
                $sample_allele->percent_of_reads,
            );
        }

        $sth->finish();
    } );

    return $sample_alleles;
}

#=method fetch_all_by_crispr
#
#  Usage       : $sample_alleles = $sample_allele_adaptor->fetch_all_by_crispr( $sample_allele_type, $date );
#  Purpose     : Fetch all sample_alleles for a given crispr
#  Returns     : ArrayRef of Crispr::SampleAllele objects
#  Parameters  : Crispr::crRNA object
#  Throws      : 
#  Comments    : None
#
#=cut
#
#sub fetch_all_by_crispr {
#    my ( $self, $crispr ) = @_;
#    my $dbh = $self->connection->dbh();
#
#    my $sql = <<'END_SQL';
#        SELECT
#            a.sample_allele_id, sample_allele_number, chr, pos, ref_sample_allele, alt_sample_allele,
#            crRNA_id
#        FROM sample_allele a, sample_allele_to_crispr ac
#        WHERE a.sample_allele_id = ac.sample_allele_id
#END_SQL
#
#    my $where_clause = 'crRNA_id = ?';
#    $sql .= 'AND ' . $where_clause;
#
#    my $sth = $self->_prepare_sql( $sql, $where_clause, [ $crispr->crRNA_id ], );
#    $sth->execute();
#
#    my ( $sample_allele_id, $sample_allele_number, $chr, $pos, $ref_sample_allele,
#        $alt_sample_allele, $crRNA_id, );
#
#    $sth->bind_columns( \( $sample_allele_id, $sample_allele_number, $chr, $pos, $ref_sample_allele,
#        $alt_sample_allele, $crRNA_id ) );
#    
#    my @sample_alleles = ();
#    while ( $sth->fetch ) {
#        my $sample_allele;
#        if( !exists $self->_sample_allele_cache->{ $sample_allele_id } ){
#            $sample_allele = Crispr::SampleAllele->new(
#                db_id => $sample_allele_id,
#                sample_allele_number => $sample_allele_number,
#                chr => $chr,
#                pos => $pos,
#                ref_sample_allele => $ref_sample_allele,
#                alt_sample_allele => $alt_sample_allele,
#            );
#            my $sample_allele_cache = $self->_sample_allele_cache;
#            $sample_allele_cache->{ $sample_allele_id } = $sample_allele;
#            $self->_set_sample_allele_cache( $sample_allele_cache );
#        }
#        else{
#            $sample_allele = $self->_sample_allele_cache->{ $sample_allele_id };
#        }
#
#        push @sample_alleles, $sample_allele;
#    }
#
#    return \@sample_alleles;
#}

=method fetch_all_by_sample

  Usage       : $sample_alleles = $sample_allele_adaptor->fetch_all_by_sample( $sample );
  Purpose     : Fetch all sample_alleles for a given sample
  Returns     : ArrayRef of Crispr::SampleAllele objects
  Parameters  : Crispr::Sample
  Throws      : 
  Comments    : None

=cut

sub fetch_all_by_sample {
    my ( $self, $sample ) = @_;
    my $sample_alleles = $self->_fetch( 'sample_id = ?', [ $sample->db_id ] );
    return $sample_alleles;
}

#_fetch
#
#Usage       : $sample_allele = $self->_fetch( $where_clause, $where_parameters );
#Purpose     : Fetch SampleAllele objects from the database with arbitrary parameteres
#Returns     : ArrayRef of Crispr::SampleAllele objects
#Parameters  : where_clause => Str (SQL where conditions)
#               where_parameters => ArrayRef of parameters to bind to sql statement
#Throws      :
#Comments    :

sub _fetch {
    my ( $self, $where_clause, $where_parameters ) = @_;
    my $dbh = $self->connection->dbh();

    my $sql = <<'END_SQL';
        SELECT
            a.allele_id, allele_number, chr, pos, ref_allele, alt_allele,
            sample_id, percentage_of_reads
        FROM allele a, sample_allele sa
        WHERE a.allele_id = sa.allele_id
END_SQL

    if ($where_clause) {
        $sql .= 'AND ' . $where_clause;
    }

    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $allele_id, $allele_number, $chr, $pos, $ref_allele,
        $alt_allele, $sample_id, $percent_of_reads, );

    $sth->bind_columns( \( $allele_id, $allele_number, $chr, $pos, $ref_allele,
        $alt_allele, $sample_id, $percent_of_reads, ) );

    my @sample_alleles = ();
    while ( $sth->fetch ) {
        my $sample_allele;
        if( !exists $self->_sample_allele_cache->{ join(q{.}, $sample_id, $allele_id, ) } ){
            # make new allele object
            my $allele_args = {
                db_id => $allele_id,
                allele_number => $allele_number,
                chr => $chr,
                pos => $pos,
                ref_allele => $ref_allele,
                alt_allele => $alt_allele,
            };
            my $allele = $self->allele_adaptor->_make_new_allele_from_db( $allele_args );
            
            # fetch sample
            my $sample = $self->sample_adaptor->fetch_by_id( $sample_id );
            
            $sample_allele = Crispr::DB::SampleAllele->new(
                sample => $sample,
                allele => $allele,
                percent_of_reads => $percent_of_reads,
            );
            my $sample_allele_cache = $self->_sample_allele_cache;
            $sample_allele_cache->{ join(q{.}, $sample_id, $allele_id, ) } = $sample_allele;
            $self->_set_sample_allele_cache( $sample_allele_cache );
        }
        else{
            $sample_allele = $self->_sample_allele_cache->{ join(q{.}, $sample_id, $allele_id, ) };
        }
        
        push @sample_alleles, $sample_allele;
    }

    return \@sample_alleles;
}

#_make_new_sample_allele_from_db
#
#Usage       : $sample_allele = $self->_make_new_sample_allele_from_db( \%fields );
#Purpose     : Create a new Crispr::DB::SampleAllele object from a db entry
#Returns     : Crispr::DB::SampleAllele object
#Parameters  : HashRef of Str
#Throws      : If no input
#               If input is not an HashRef
#Comments    : 

sub _make_new_sample_allele_from_db {
    my ( $self, $args ) = @_;

    if( !$args ){
        die "NO INPUT!";
    }
    elsif( ref $args ne 'HASH' ){
        die "INPUT NOT HASHREF!";
    }
    my $sample_allele;

    if( !exists $self->_sample_allele_cache->{ $args->{db_id} } ){
        $sample_allele = Crispr::DB::SampleAllele->new( $args );
        my $sample_allele_cache = $self->_sample_allele_cache;
        $sample_allele_cache->{ $args->{db_id} } = $sample_allele;
        $self->_set_sample_allele_cache( $sample_allele_cache );
    }
    else{
        $sample_allele = $self->_sample_allele_cache->{ $args->{db_id} };
    }

    return $sample_allele;
}

=method delete_sample_allele_from_db

  Usage       : $sample_allele_adaptor->delete_sample_allele_from_db( $sample_allele );
  Purpose     : Delete a sample_allele from the database
  Returns     : Crispr::DB::SampleAllele object
  Parameters  : Crispr::DB::SampleAllele object
  Throws      :
  Comments    : Not implemented yet.

=cut

sub delete_sample_allele_from_db {
    #my ( $self, $sample_allele ) = @_;

    # first check sample_allele exists in db

    # delete primers and primer pairs

    # delete transcripts

    # if sample_allele has talen pairs, delete tale and talen pairs

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

#_build_crRNA_adaptor

  #Usage       : $crRNA_adaptor = $self->_build_crRNA_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::InjectionPoolAdaptor
  #Returns     : Crispr::DB::InjectionPoolAdaptor
  #Parameters  : None
  #Throws      :
  #Comments    :

sub _build_crRNA_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'crRNA' );
}

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

    my $sample_allele_adaptor = $db_connection->get_adaptor( 'sample_allele' );

    # store an sample_allele object in the db
    $sample_allele_adaptor->store( $sample_allele );

    # retrieve an sample_allele by id
    my $sample_allele = $sample_allele_adaptor->fetch_by_id( '214' );


=head1 DESCRIPTION

 An SampleAlleleAdaptor is an object used for storing and retrieving SampleAllele objects in an SQL database.
 The recommended way to use this module is through the DBConnection object as shown above.
 This allows a single open connection to the database which can be shared between multiple database adaptors.

=head1 DIAGNOSTICS


=head1 CONFIGURATION AND ENVIRONMENT


=head1 DEPENDENCIES


=head1 INCOMPATIBILITIES
