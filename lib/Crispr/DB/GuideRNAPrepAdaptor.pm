## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::GuideRNAPrepAdaptor;
## use critic

# ABSTRACT: GuideRNAPrepAdaptor object - object for storing GuideRNAPrep objects in and retrieving them from a SQL database

use namespace::autoclean;
use Moose;
use DateTime;
use Carp qw( cluck confess );
use English qw( -no_match_vars );
use Crispr::DB::GuideRNAPrep;
use Crispr::crRNA;

extends 'Crispr::DB::BaseAdaptor';

=method new

  Usage       : my $guideRNA_prep_adaptor = Crispr::DB::GuideRNAPrepAdaptor->new(
					db_connection => $db_connection,
                );
  Purpose     : Constructor for creating guideRNA_prep adaptor objects
  Returns     : Crispr::DB::GuideRNAPrepAdaptor object
  Parameters  :     db_connection => Crispr::DB::DBConnection object,
  Throws      : If parameters are not the correct type
  Comments    : The preferred method for constructing a GuideRNAPrepAdaptor is to use the
                get_adaptor method with a previously constructed DBConnection object

=cut

=method crRNA_adaptor

  Usage       : $self->crRNA_adaptor();
  Purpose     : Getter for a crRNA_adaptor.
  Returns     : Crispr::crRNAAdaptor
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'crRNA_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::crRNAAdaptor',
    lazy => 1,
    builder => '_build_crRNA_adaptor',
);

=method plate_adaptor

  Usage       : $self->plate_adaptor();
  Purpose     : Getter for a plate_adaptor.
  Returns     : Crispr::PlateAdaptor
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'plate_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::PlateAdaptor',
    lazy => 1,
    builder => '_build_plate_adaptor',
);

=method store

  Usage       : $guideRNA_prep = $guideRNA_prep_adaptor->store( $guideRNA_prep );
  Purpose     : Store a guideRNA_prep object in the database
  Returns     : Crispr::DB::GuideRNAPrep object
  Parameters  : Crispr::DB::GuideRNAPrep object
  Throws      : If argument is not a GuideRNAPrep object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : 

=cut

sub store {
    my ( $self, $guideRNA_prep, ) = @_;
	# make an arrayref with this one guideRNA_prep and call store_guideRNA_preps
	my $guideRNA_preps = $self->store_guideRNA_preps( [ $guideRNA_prep ] );
	
	return $guideRNA_preps->[0];
}

=method store_guideRNA_prep

  Usage       : $guideRNA_prep = $guideRNA_prep_adaptor->store_guideRNA_prep( $guideRNA_prep );
  Purpose     : Store a guideRNA_prep in the database
  Returns     : Crispr::DB::GuideRNAPrep object
  Parameters  : Crispr::DB::GuideRNAPrep object
  Throws      : If argument is not a GuideRNAPrep object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : Synonym for store

=cut

sub store_guideRNA_prep {
    my ( $self, $guideRNA_prep, ) = @_;
	return $self->store( $guideRNA_prep );
}

=method store_guideRNA_preps

  Usage       : $guideRNA_preps = $guideRNA_prep_adaptor->store_guideRNA_preps( $guideRNA_preps );
  Purpose     : Store a set of guideRNA_preps in the database
  Returns     : ArrayRef of Crispr::DB::GuideRNAPrep objects
  Parameters  : ArrayRef of Crispr::DB::GuideRNAPrep objects
  Throws      : If argument is not an ArrayRef
                If objects in ArrayRef are not Crispr::DB::GuideRNAPrep objects
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None
   
=cut

sub store_guideRNA_preps {
    my ( $self, $guideRNA_preps, ) = @_;
    my $dbh = $self->connection->dbh();
    
	confess "Supplied argument must be an ArrayRef of GuideRNAPrep objects.\n" if( ref $guideRNA_preps ne 'ARRAY');
	foreach ( @{$guideRNA_preps} ){
        if( !ref $_ || !$_->isa('Crispr::DB::GuideRNAPrep') ){
            confess "Argument must be Crispr::DB::GuideRNAPrep objects.\n";
        }
    }
	
    my $statement = "insert into guideRNA_prep values( ?, ?, ?, ?, ?, ?, ?, ? );"; 
    
    $self->connection->txn(  fixup => sub {
		my $sth = $dbh->prepare($statement);
		
		foreach my $guideRNA_prep ( @$guideRNA_preps ){
            my $well_id;
            my $plate_id;
            if( defined $guideRNA_prep->well ){
                $well_id = $guideRNA_prep->well->position;
                if( defined $guideRNA_prep->well->plate ){
                    $plate_id = $guideRNA_prep->well->plate->plate_id;
                }
            }
            
			$sth->execute($guideRNA_prep->db_id, $guideRNA_prep->crRNA_id,
				$guideRNA_prep->type, $guideRNA_prep->concentration,
				$guideRNA_prep->made_by, $guideRNA_prep->date,
				$plate_id, $well_id,
            );
			
			my $last_id;
			$last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'guideRNA_prep', 'guideRNA_prep_id' );
			$guideRNA_prep->db_id( $last_id );
		}
		
		$sth->finish();
    } );
    
    return $guideRNA_preps;
}

=method fetch_by_id

  Usage       : $guideRNA_prep = $guideRNA_prep_adaptor->fetch_by_id( $guideRNA_prep_id );
  Purpose     : Fetch a guideRNA_prep given its database id
  Returns     : Crispr::DB::GuideRNAPrep object
  Parameters  : crispr-db guideRNA_prep_id - Int
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_by_id {
    my ( $self, $id ) = @_;

    my $guideRNA_prep = $self->_fetch( 'guideRNA_prep_id = ?', [ $id ] )->[0];
    
    if( !$guideRNA_prep ){
        confess "Couldn't retrieve guideRNA_prep, $id, from database.\n";
    }
    return $guideRNA_prep;
}

=method fetch_by_ids

  Usage       : $guideRNA_preps = $guideRNA_prep_adaptor->fetch_by_ids( \@guideRNA_prep_ids );
  Purpose     : Fetch a list of guideRNA_preps given a list of db ids
  Returns     : Arrayref of Crispr::DB::GuideRNAPrep objects
  Parameters  : Arrayref of crispr-db guideRNA_prep ids
  Throws      : If no rows are returned from the database for one of ids
  Comments    : None

=cut

sub fetch_by_ids {
    my ( $self, $ids ) = @_;
	my @guideRNA_preps;
    foreach my $id ( @{$ids} ){
        push @guideRNA_preps, $self->fetch_by_id( $id );
    }
	
    return \@guideRNA_preps;
}

#=method fetch_by_type
#
#  Usage       : $guideRNA_preps = $guideRNA_prep_adaptor->fetch_by_type( $guideRNA_prep );
#  Purpose     : Fetch a guideRNA_prep object by type
#  Returns     : Crispr::DB::GuideRNAPrep object
#  Parameters  : type => Str
#  Throws      : If no rows are returned from the database
#  Comments    : None
#
#=cut
#
#sub fetch_by_type {
#    my ( $self, $type ) = @_;
#
#    my $guideRNA_prep = $self->_fetch( 'guideRNA_type = ?', [ $type, ] )->[0];
#    
#    if( !$guideRNA_prep ){
#        confess "Couldn't retrieve guideRNA_prep from database.\n";
#    }
#    return $guideRNA_prep;
#}

=method fetch_all_by_crRNA_id

  Usage       : $guideRNA_preps = $guideRNA_prep_adaptor->fetch_all_by_crRNA_id( 1 );
  Purpose     : Fetch a guideRNA_prep object by crRNA_id
  Returns     : Crispr::DB::GuideRNAPrep object
  Parameters  : plasmid name => Str
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_crRNA_id {
    my ( $self, $crRNA_id ) = @_;
    
    my $statement = "gp.crRNA_id = ?;";
    my $guideRNA_preps = $self->_fetch( $statement, [ $crRNA_id, ], );
    return $guideRNA_preps;
}

=method fetch_all_by_injection_pool

  Usage       : $guideRNA_preps = $guideRNA_prep_adaptor->fetch_all_by_injection_pool( $inj_pool );
  Purpose     : Fetch a guideRNA_prep object by InjectionPool object
  Returns     : Crispr::DB::GuideRNAPrep object
  Parameters  : plasmid name => Str
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_injection_pool {
    my ( $self, $inj_pool ) = @_;
    
    # check object is an InjectionPool object
    if( !ref $inj_pool || !$inj_pool->isa('Crispr::DB::InjectionPool') ){
        confess "The supplied object should be a Crispr::DB::InjectionPool object, not a ",
            ref $inj_pool || 'String';
    }
    # sql statement
    my $sql = <<'END_SQL';
        SELECT
			gp.guideRNA_prep_id, gp.guideRNA_type, gp.concentration,
            gp.made_by, gp.date, gp.well_id,
            cr.crRNA_id, crRNA_name, chr, start, end, strand,
            sequence, num_five_prime_Gs, score, coding_score,
            pl.plate_id, plate_name, plate_type,
            plate_category, ordered, received, 
            guideRNA_concentration
        FROM guideRNA_prep gp, crRNA cr, plate pl, injection i, injection_pool ip
        WHERE gp.crRNA_id = cr.crRNA_id AND
        gp.plate_id = pl.plate_id AND
        gp.guideRNA_prep_id = ip.guideRNA_prep_id AND
        i.injection_id = ip.injection_id
END_SQL
    
    # check that either db_id or injection_name is defined
    my $params;
    if( defined $inj_pool->db_id ){
        $sql .= "AND ip.injection_id = ?;";
        $params = [ $inj_pool->db_id ];
    }
    elsif( defined $inj_pool->pool_name ){
        $sql .= "AND i.injection_name = ?;";
        $params = [ $inj_pool->pool_name ];
    }
    
    my $results;
    my $guideRNA_preps;
    eval{
        $results = $self->fetch_rows_for_generic_select_statement( $sql, $params, );
    };
    if( $EVAL_ERROR ){
        if( $EVAL_ERROR eq 'NO ROWS' ){
            warn "Couldn't find any guide RNA preps for the supplied injection pool, ",
                $params->[0], "\n";
        }
        else{
            confess $EVAL_ERROR, "\n";
        }
    }
    else{
        foreach my $row ( @{$results} ){
            push @{$guideRNA_preps}, $self->_make_new_guideRNA_prep_from_db( $row );
        }
    }
    
    return $guideRNA_preps;
}
 
#_fetch
#
#Usage       : $guideRNA_prep = $self->_fetch( $where_clause, $where_parameters );
#Purpose     : Fetch GuideRNAPrep objects from the database with arbitrary parameteres
#Returns     : ArrayRef of Crispr::DB::GuideRNAPrep objects
#Parameters  : where_clause => Str (SQL where conditions)
#               where_parameters => ArrayRef of parameters to bind to sql statement
#Throws      : 
#Comments    :

my %guideRNA_prep_cache;
sub _fetch {
    my ( $self, $where_clause, $where_parameters ) = @_;
    my $dbh = $self->connection->dbh();
    
    my $sql = <<'END_SQL';
        SELECT
			guideRNA_prep_id,
            guideRNA_type,
            concentration,
            made_by,
            date,
            gp.well_id,
            cr.crRNA_id, crRNA_name, chr, start, end, strand,
            sequence, num_five_prime_Gs, score, coding_score,
            pl.plate_id, plate_name, plate_type,
            plate_category, ordered, received
        FROM guideRNA_prep gp, crRNA cr, plate pl
        WHERE gp.crRNA_id = cr.crRNA_id AND
        gp.plate_id = pl.plate_id 
END_SQL

    if ($where_clause) {
        $sql .= 'AND ' . $where_clause;
    }

    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $guideRNA_prep_id, $guideRNA_type, $concentration,
        $made_by, $date, $well_id, $crRNA_id,
        $crRNA_name, $chr, $start, $end, $strand,
        $sequence, $num_five_prime_Gs, $score, $coding_score,
        $plate_id, $plate_name, $plate_type,
        $plate_category, $ordered, $received );
    
    $sth->bind_columns( \( $guideRNA_prep_id, $guideRNA_type, $concentration,
        $made_by, $date, $well_id, $crRNA_id,
        $crRNA_name, $chr, $start, $end, $strand,
        $sequence, $num_five_prime_Gs, $score, $coding_score,
        $plate_id, $plate_name, $plate_type,
        $plate_category, $ordered, $received ) );

    my @guideRNA_preps = ();
    while ( $sth->fetch ) {
        my $guideRNA_prep;
        if( !exists $guideRNA_prep_cache{ $guideRNA_prep_id } ){
            my $crRNA = $self->crRNA_adaptor->_make_new_crRNA_from_db(
                [ $crRNA_id, $crRNA_name, $chr, $start, $end, $strand,
                $sequence, $num_five_prime_Gs, $score, $coding_score, ]
            );
            
            my $plate = $self->plate_adaptor->_make_new_plate_from_db(
                [ $plate_id, $plate_name, $plate_type,
                $plate_category, $ordered, $received ]
            );
            my $well = Labware::Well->new(
                position => $well_id,
                plate => $plate,
            );
            
            $guideRNA_prep = Crispr::DB::GuideRNAPrep->new(
                db_id => $guideRNA_prep_id,
                crRNA => $crRNA,
                guideRNA_type => $guideRNA_type,
                concentration => $concentration,
                made_by => $made_by,
                date => $date,
                well => $well,
            );
            $guideRNA_prep_cache{ $guideRNA_prep_id } = $guideRNA_prep;
        }
        else{
            $guideRNA_prep = $guideRNA_prep_cache{ $guideRNA_prep_id };
        }
        
        push @guideRNA_preps, $guideRNA_prep;
    }

    return \@guideRNA_preps;    
}

#_make_new_guideRNA_prep_from_db
#
#Usage       : $guideRNA_prep = $self->_make_new_guideRNA_prep_from_db( \@fields );
#Purpose     : Create a new Crispr::DB::GuideRNAPrep object from a db entry
#Returns     : Crispr::DB::GuideRNAPrep object
#Parameters  : ArrayRef of Str
#Throws      : 
#Comments    : Expects fields to be in table order ie db_id, guideRNA_type, concentration, made_by, date etc

sub _make_new_guideRNA_prep_from_db {
    my ( $self, $fields ) = @_;
    my $guideRNA_prep;
	
    if( !exists $guideRNA_prep_cache{ $fields->[0] } ){
        my ( $crRNA, $plate, $well, );
        if( defined $fields->[6] ){
            $crRNA = $self->crRNA_adaptor->_make_new_crRNA_from_db(
                [ @{$fields}[6..15] ],
            );
        }
        if( defined $fields->[16] ){
            $plate = $self->plate_adaptor->_make_new_plate_from_db(
                [ @{$fields}[16..21] ]
            );
        }
        if( $fields->[5] ){
            $well = Labware::Well->new(
                position => $fields->[5],
                plate => $plate,
            );
        }
        
        $guideRNA_prep = Crispr::DB::GuideRNAPrep->new(
            db_id => $fields->[0],
            crRNA => $crRNA,
            guideRNA_type => $fields->[1],
            concentration => $fields->[2],
            made_by => $fields->[3],
            date => $fields->[4],
            well => $well,
        );
        $guideRNA_prep_cache{ $fields->[0] } = $guideRNA_prep;
    }
    else{
        $guideRNA_prep = $guideRNA_prep_cache{ $fields->[0] };
    }
	
    return $guideRNA_prep;
}

sub delete_guideRNA_prep_from_db {
	#my ( $self, $guideRNA_prep ) = @_;
	
	# first check guideRNA_prep exists in db
	
	# delete primers and primer pairs
	
	# delete transcripts
	
	# if guideRNA_prep has talen pairs, delete tale and talen pairs

}

#_build_crRNA_adaptor

  #Usage       : $crRNAs = $crRNA_adaptor->_build_crRNA_adaptor( $well, $type );
  #Purpose     : Internal method to create a new Crispr::crRNAAdaptor
  #Returns     : Crispr::crRNAAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_crRNA_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'crRNA' );
}

#_build_plate_adaptor

  #Usage       : $crRNAs = $crRNA_adaptor->_build_plate_adaptor( $well, $type );
  #Purpose     : Internal method to create a new Crispr::PlateAdaptor
  #Returns     : Crispr::PlateAdaptor
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
  
    my $guideRNA_prep_adaptor = $db_connection->get_adaptor( 'guideRNA_prep' );
    
    # store a guideRNA_prep object in the db
    $guideRNA_prep_adaptor->store( $guideRNA_prep );
    
    # retrieve a guideRNA_prep by id
    my $guideRNA_prep = $guideRNA_prep_adaptor->fetch_by_id( '214' );
  
    # retrieve a guideRNA_prep by combination of type and date
    my $guideRNA_prep = $guideRNA_prep_adaptor->fetch_by_type_and_date( 'guideRNA_prep_dnls_native', '2015-04-27' );
    

=head1 DESCRIPTION
 
 A GuideRNAPrepAdaptor is an object used for storing and retrieving GuideRNAPrep objects in an SQL database.
 The recommended way to use this module is through the DBAdaptor object as shown above.
 This allows a single open connection to the database which can be shared between multiple database adaptors.
 
=head1 DIAGNOSTICS
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
=head1 DEPENDENCIES
 
 
=head1 INCOMPATIBILITIES
 
