## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::AlleleAdaptor;

## use critic

# ABSTRACT: AlleleAdaptor object - object for storing Allele objects in and retrieving them from an SQL database

use namespace::autoclean;
use Moose;
use DateTime;
use Carp qw( cluck confess );
use English qw( -no_match_vars );
use Crispr::Allele;

extends 'Crispr::DB::BaseAdaptor';

=method new

  Usage       : my $allele_adaptor = Crispr::DB::AlleleAdaptor->new(
                    db_connection => $db_connection,
                );
  Purpose     : Constructor for creating allele adaptor objects
  Returns     : Crispr::DB::AlleleAdaptor object
  Parameters  :     db_connection => Crispr::DB::DBConnection object,
  Throws      : If parameters are not the correct type
  Comments    : The preferred method for constructing a AlleleAdaptor is to use the
                get_adaptor method with a previously constructed DBConnection object

=cut

# cache for allele objects from db
has '_allele_cache' => (
	is => 'ro',
	isa => 'HashRef',
    init_arg => undef,
    writer => '_set_allele_cache',
    default => sub { return {}; },
);

=method store

  Usage       : $allele = $allele_adaptor->store( $allele );
  Purpose     : Store a allele object in the database
  Returns     : Crispr::Allele object
  Parameters  : Crispr::Allele object
  Throws      : If argument is not a Allele object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    :

=cut

sub store {
    my ( $self, $allele, ) = @_;
    # make an arrayref with this one allele and call store_alleles
    my @alleles = ( $allele );
    my $alleles = $self->store_alleles( \@alleles );

    return $alleles->[0];
}

=method store_allele

  Usage       : $allele = $allele_adaptor->store_allele( $allele );
  Purpose     : Store a allele in the database
  Returns     : Crispr::Allele object
  Parameters  : Crispr::Allele object
  Throws      : If argument is not a Allele object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : Synonym for store

=cut

sub store_allele {
    my ( $self, $allele, ) = @_;
    return $self->store( $allele );
}

=method store_alleles

  Usage       : $alleles = $allele_adaptor->store_alleles( $alleles );
  Purpose     : Store a set of alleles in the database
  Returns     : ArrayRef of Crispr::Allele objects
  Parameters  : ArrayRef of Crispr::Allele objects
  Throws      : If argument is not an ArrayRef
                If objects in ArrayRef are not Crispr::Allele objects
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None

=cut

sub store_alleles {
    my $self = shift;
    my $alleles = shift;
    my $dbh = $self->connection->dbh();

    confess "Supplied argument must be an ArrayRef of Allele objects.\n" if( ref $alleles ne 'ARRAY');
    foreach ( @{$alleles} ){
        if( !ref $_ || !$_->isa('Crispr::Allele') ){
            confess "Argument must be Crispr::Allele objects.\n";
        }
    }

    my $statement = "insert into allele values( ?, ?, ?, ?, ?, ? );";

    $self->connection->txn(  fixup => sub {
        my $sth = $dbh->prepare($statement);

        foreach my $allele ( @$alleles ){
            $sth->execute($allele->db_id,
                $allele->allele_number,
                $allele->chr,
                $allele->pos,
                $allele->ref_allele,
                $allele->alt_allele,
            );

            my $last_id;
            $last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'allele', 'allele_id' );
            $allele->db_id( $last_id );
            
            # add crisprs to crispr_to_allele
            if( defined $allele->crisprs ){
                $self->store_crisprs_for_allele( $allele );
            }
        }

        $sth->finish();
    } );

    return $alleles;
}

=method store_crisprs_for_allele

  Usage       : $allele = $allele_adaptor->store_crisprs_for_allele( $allele );
  Purpose     : Store the ids of the crisprs associated with this allele in the allele_to_crispr table
  Returns     : Crispr::Allele object
  Parameters  : Crispr::Allele object
  Throws      : 
  Comments    : None

=cut

sub store_crisprs_for_allele {
    my ( $self, $allele, ) = @_;
    my $dbh = $self->connection->dbh();
    
    my $statement = "insert into allele_to_crispr values( ?, ? );";
    $self->connection->txn(  fixup => sub {
        my $sth = $dbh->prepare($statement);
        foreach my $crispr ( @{$allele->crisprs} ){
            $sth->execute(
                $allele->db_id,
                $crispr->crRNA_id,
            );
        }
        $sth->finish();
    } );

    return 1;
}

=method allele_exists_in_db

  Usage       : $exists = $allele_adaptor->allele_exists_in_db( $allele );
  Purpose     : Fetch a allele given its database id
  Returns     : 1 OR 0
  Parameters  : Crispr::Allele object
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub allele_exists_in_db {
    my ( $self, $allele ) = @_;
    
    my ($check_statement, $params);
    if( $allele->db_id ){
        $check_statement = 'select count(*) from allele where allele_id = ?';
        $params = [ $allele->db_id ];
    }
    elsif( $allele->chr && $allele->pos && $allele->ref_allele && $allele->alt_allele ){
        $check_statement = 'select count(*) from allele where chr = ? AND pos = ? AND ref_allele = ? AND alt_allele = ?';
        $params = [ $allele->chr, $allele->pos, $allele->ref_allele, $allele->alt_allele ];
    }
    elsif( defined $allele->allele_number ){
        $check_statement = "SELECT count(*) FROM allele WHERE allele_number = ?;";
        $params = [ $allele->allele_number ];
    }
    
    my $exists;
    eval{
        $exists = $self->check_entry_exists_in_db( $check_statement, $params );
    };
    if( $EVAL_ERROR ){
        die $EVAL_ERROR;
    }
    return $exists;
}

=method fetch_by_id

  Usage       : $allele = $allele_adaptor->fetch_by_id( $allele_id );
  Purpose     : Fetch a allele given its database id
  Returns     : Crispr::Allele object
  Parameters  : crispr-db allele_id - Int
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_by_id {
    my ( $self, $id ) = @_;

    my $allele;
    if( exists $self->_allele_cache->{ $id } ){
        $allele = $self->_allele_cache->{ $id };
    } else{
        $allele = $self->_fetch( 'a.allele_id = ?', [ $id ] )->[0];
    }

    if( !$allele ){
        confess "Couldn't retrieve allele, $id, from database.\n";
    }
    return $allele;
}

=method fetch_by_ids

  Usage       : $alleles = $allele_adaptor->fetch_by_ids( \@allele_ids );
  Purpose     : Fetch a list of alleles given a list of db ids
  Returns     : Arrayref of Crispr::Allele objects
  Parameters  : Arrayref of crispr-db allele ids
  Throws      : If no rows are returned from the database for one of ids
  Comments    : None

=cut

sub fetch_by_ids {
    my ( $self, $ids ) = @_;
    my @alleles;
    foreach my $id ( @{$ids} ){
        push @alleles, $self->fetch_by_id( $id );
    }

    return \@alleles;
}

=method fetch_by_allele_number

  Usage       : $alleles = $allele_adaptor->fetch_by_allele_number( $allele_num );
  Purpose     : Fetch allele object by allele number
  Returns     : Crispr::Allele object
  Parameters  : Allele number => Int
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_by_allele_number {
    my ( $self, $allele_number ) = @_;

    my $alleles = $self->_fetch( 'allele_number = ?', [ $allele_number, ] );

    if( !$alleles ){
        confess "Couldn't retrieve allele from database with allele_number, $allele_number.\n";
    }
    else{
        return $alleles->[0];
    }
}

=method fetch_by_variant_description

  Usage       : $alleles = $allele_adaptor->fetch_by_variant_description( $allele_num );
  Purpose     : Fetch allele object by allele number
  Returns     : Crispr::Allele object
  Parameters  : Allele number => Int
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_by_variant_description {
    my ( $self, $variant_description ) = @_;
    my ( $chr, $pos, $ref, $alt, ) = split /:/, $variant_description;
    my $alleles = $self->_fetch( 'chr = ? AND pos = ? AND ref_allele = ? AND alt_allele = ?',
                                [ $chr, $pos, $ref, $alt, ] );

    if( !$alleles ){
        confess "Couldn't retrieve allele from database with variant, $variant_description.\n";
    }
    else{
        return $alleles->[0];
    }
}

=method fetch_all_by_crispr

  Usage       : $alleles = $allele_adaptor->fetch_all_by_crispr( $allele_type, $date );
  Purpose     : Fetch all alleles for a given crispr
  Returns     : ArrayRef of Crispr::Allele objects
  Parameters  : Crispr::crRNA object
  Throws      : 
  Comments    : None

=cut

sub fetch_all_by_crispr {
    my ( $self, $crispr ) = @_;
    my $dbh = $self->connection->dbh();

    my $sql = <<'END_SQL';
        SELECT
            a.allele_id, allele_number, chr, pos, ref_allele, alt_allele,
            crRNA_id
        FROM allele a, allele_to_crispr ac
        WHERE a.allele_id = ac.allele_id
END_SQL

    my $where_clause = 'crRNA_id = ?';
    $sql .= 'AND ' . $where_clause;

    my $sth = $self->_prepare_sql( $sql, $where_clause, [ $crispr->crRNA_id ], );
    $sth->execute();

    my ( $allele_id, $allele_number, $chr, $pos, $ref_allele,
        $alt_allele, $crRNA_id, );

    $sth->bind_columns( \( $allele_id, $allele_number, $chr, $pos, $ref_allele,
        $alt_allele, $crRNA_id ) );
    
    my @alleles = ();
    while ( $sth->fetch ) {
        my $allele;
        if( !exists $self->_allele_cache->{ $allele_id } ){
            $allele = Crispr::Allele->new(
                db_id => $allele_id,
                allele_number => $allele_number,
                chr => $chr,
                pos => $pos,
                ref_allele => $ref_allele,
                alt_allele => $alt_allele,
            );
            my $allele_cache = $self->_allele_cache;
            $allele_cache->{ $allele_id } = $allele;
            $self->_set_allele_cache( $allele_cache );
        }
        else{
            $allele = $self->_allele_cache->{ $allele_id };
        }

        push @alleles, $allele;
    }

    return \@alleles;
}

=method fetch_all_by_sample

  Usage       : $alleles = $allele_adaptor->fetch_all_by_sample( $sample );
  Purpose     : Fetch all alleles for a given sample
  Returns     : ArrayRef of Crispr::Allele objects
  Parameters  : Crispr::Sample
  Throws      : 
  Comments    : None

=cut

sub fetch_all_by_sample {
    my ( $self, $sample ) = @_;
    my $dbh = $self->connection->dbh();

    my $sql = <<'END_SQL';
        SELECT
            a.allele_id, allele_number, chr, pos, ref_allele, alt_allele,
            sample_id, percentage_of_reads
        FROM allele a, sample_allele sa
        WHERE a.allele_id = sa.allele_id
END_SQL

    my $where_clause = 'sample_id = ?';
    $sql .= 'AND ' . $where_clause;

    my $sth = $self->_prepare_sql( $sql, $where_clause, [ $sample->db_id ], );
    $sth->execute();

    my ( $allele_id, $allele_number, $chr, $pos, $ref_allele,
        $alt_allele, $sample_id, $percentage_of_reads, );

    $sth->bind_columns( \( $allele_id, $allele_number, $chr, $pos, $ref_allele,
        $alt_allele, $sample_id, $percentage_of_reads, ) );
    
    my @alleles = ();
    while ( $sth->fetch ) {
        my $allele = Crispr::Allele->new(
            db_id => $allele_id,
            allele_number => $allele_number,
            chr => $chr,
            pos => $pos,
            ref_allele => $ref_allele,
            alt_allele => $alt_allele,
            percent_of_reads => $percentage_of_reads,
        );
        push @alleles, $allele;
    }

    $sample->alleles( \@alleles );
    return \@alleles;
}

=method get_db_id_by_variant_description

  Usage       : $allele = $allele_adaptor->get_db_id_by_variant_description( $variant_description );
  Purpose     : Get the database id of a Allele given it's name.
  Returns     : Int
  Parameters  : Allele name - Str
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub get_db_id_by_variant_description {
    my ( $self, $variant_description ) = @_;
    my $allele = $self->fetch_by_variant_description( $variant_description );
    return $allele->db_id;
}

#_fetch
#
#Usage       : $allele = $self->_fetch( $where_clause, $where_parameters );
#Purpose     : Fetch Allele objects from the database with arbitrary parameteres
#Returns     : ArrayRef of Crispr::Allele objects
#Parameters  : where_clause => Str (SQL where conditions)
#               where_parameters => ArrayRef of parameters to bind to sql statement
#Throws      :
#Comments    :

sub _fetch {
    my ( $self, $where_clause, $where_parameters ) = @_;
    my $dbh = $self->connection->dbh();

    my $sql = <<'END_SQL';
        SELECT
            a.allele_id,
            allele_number,
            chr,
            pos,
            ref_allele,
            alt_allele
        FROM allele a
END_SQL

    if ($where_clause) {
        $sql .= 'WHERE ' . $where_clause;
    }

    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $allele_id, $allele_number, $chr, $pos, $ref_allele,
        $alt_allele );

    $sth->bind_columns( \( $allele_id, $allele_number, $chr, $pos, $ref_allele,
        $alt_allele, ) );

    my @alleles = ();
    while ( $sth->fetch ) {
        my $allele;
        if( !exists $self->_allele_cache->{ $allele_id } ){
            $allele = Crispr::Allele->new(
                db_id => $allele_id,
                allele_number => $allele_number,
                chr => $chr,
                pos => $pos,
                ref_allele => $ref_allele,
                alt_allele => $alt_allele,
            );
            my $allele_cache = $self->_allele_cache;
            $allele_cache->{ $allele_id } = $allele;
            $self->_set_allele_cache( $allele_cache );
        }
        else{
            $allele = $self->_allele_cache->{ $allele_id };
        }
#        my $crisprs = $self->crRNA_adaptor->fetch_crisprs_by_allele( $allele );

        push @alleles, $allele;
    }

    return \@alleles;
}

#_make_new_allele_from_db
#
#Usage       : $allele = $self->_make_new_allele_from_db( \%fields );
#Purpose     : Create a new Crispr::DB::Allele object from a db entry
#Returns     : Crispr::DB::Allele object
#Parameters  : HashRef of Str
#Throws      : If no input
#               If input is not an HashRef
#Comments    : 

sub _make_new_allele_from_db {
    my ( $self, $args ) = @_;

    if( !$args ){
        die "NO INPUT!";
    }
    elsif( ref $args ne 'HASH' ){
        die "INPUT NOT HASHREF!";
    }
    my $allele;

    if( !exists $self->_allele_cache->{ $args->{db_id} } ){
        $allele = Crispr::Allele->new( $args );
        my $allele_cache = $self->_allele_cache;
        $allele_cache->{ $args->{db_id} } = $allele;
        $self->_set_allele_cache( $allele_cache );
    }
    else{
        $allele = $self->_allele_cache->{ $args->{db_id} };
    }

    return $allele;
}

=method delete_allele_from_db

  Usage       : $allele_adaptor->delete_allele_from_db( $allele );
  Purpose     : Delete a allele from the database
  Returns     : Crispr::DB::Allele object
  Parameters  : Crispr::DB::Allele object
  Throws      :
  Comments    : Not implemented yet.

=cut

sub delete_allele_from_db {
    #my ( $self, $allele ) = @_;

    # first check allele exists in db

    # delete primers and primer pairs

    # delete transcripts

    # if allele has talen pairs, delete tale and talen pairs

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

    my $allele_adaptor = $db_connection->get_adaptor( 'allele' );

    # store an allele object in the db
    $allele_adaptor->store( $allele );

    # retrieve an allele by id
    my $allele = $allele_adaptor->fetch_by_id( '214' );


=head1 DESCRIPTION

 An AlleleAdaptor is an object used for storing and retrieving Allele objects in an SQL database.
 The recommended way to use this module is through the DBConnection object as shown above.
 This allows a single open connection to the database which can be shared between multiple database adaptors.

=head1 DIAGNOSTICS


=head1 CONFIGURATION AND ENVIRONMENT


=head1 DEPENDENCIES


=head1 INCOMPATIBILITIES
