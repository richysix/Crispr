## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::PlateAdaptor;

## use critic

# ABSTRACT: PlateAdaptor - object for storing Plate objects in and
# retrieving them from an SQL database.

use warnings;
use strict;
use namespace::autoclean;
use Moose;
use Crispr::Target;
use Crispr::crRNA;
use Crispr::Plate;
use Carp qw( cluck confess );
use English qw( -no_match_vars );

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

=method store

  Usage       : $plate_adaptor->store;
  Purpose     : Stores a plate in the db
  Returns     : Crispr::Plate
  Parameters  : Crispr::Plate
  Throws      : If plate is not supplied
                If supplied parameter is not a Crispr::Plate object
  Comments    : 

=cut

sub store {
    my ( $self, $plate ) = @_;
    my $dbh = $self->connection->dbh();
    
	# check that plate object has been supplied and is a Crispr::Plate
	if( !$plate ){
		confess "Plate must be supplied in order to add it to the database!\n";
	}
	if( !ref $plate ){
		confess "Supplied object must be a Crispr::Plate object!\n";
	}
	if( ref $plate && !$plate->isa('Crispr::Plate') ){
		confess "Supplied object must be a Crispr::Plate object, not ", ref $plate, ".\n";
	}
	
    # check whether plate already exists
	my $check_plate_st = 'select count(*) from plate where plate_name = ?';
	if( $self->check_entry_exists_in_db( $check_plate_st, [ $plate->plate_name ] ) ){
        # get plate_id from db
        my $st = 'select plate_id from plate where plate_name = ?';
        my $results = $self->fetch_rows_expecting_single_row( $st, [ $plate->plate_name ] );
        $plate->plate_id( $results->[0] );
        die "PLATE ALREADY EXISTS";
	}
    
	# statement - insert values into table plate
    my $statement = "insert into plate values( ?, ?, ?, ?, ?, ? );";
	#my $plate_name;
    
    $self->connection->txn(  fixup => sub {
		my $sth ;
        if( !$plate->plate_name ){
            confess "Plate must have a plate_name to enter it into the database";
        }
        # add plate to db
		$sth = $dbh->prepare($statement);
        $sth->execute( $plate->plate_id, $plate->plate_name,
			$plate->plate_type, $plate->plate_category,
            $plate->ordered, $plate->received,
        );
		
		my $last_id;
		$last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'crRNA', 'crRNA_id' );
		$plate->plate_id( $last_id );
		$sth->finish();
    } );
	
    return $plate;
}

=method get_plate_id_from_name

  Usage       : $plate_adaptor->get_plate_id_from_name;
  Purpose     : Stores a plate in the db
  Returns     : Crispr::::Plate
  Parameters  : Crispr::::Plate
  Throws      : If plate is not supplied
                If supplied parameter is not a Crispr::Plate object
  Comments    : 

=cut


sub get_plate_id_from_name {
    my ( $self, $plate_name ) = @_;
    my $plate_id;
	# statement - fetch plate by id
	my $plate = $self->fetch_empty_plate_by_name( $plate_name );
	return $plate->plate_id;
}

=method fetch_empty_plate_by_id

  Usage       : $plate_adaptor->fetch_empty_plate_by_id;
  Purpose     : Stores a plate in the db
  Returns     : Crispr::Plate
  Parameters  : Crispr::Plate
  Throws      : If plate is not supplied
                If supplied parameter is not a Crispr::Plate object
  Comments    : 

=cut

sub fetch_empty_plate_by_id {
    my ( $self, $plate_id ) = @_;
    # statement - fetch plate by id
    my $statement = "select * from plate where plate_id = ?;";
    
    my ( $plate, $num_rows ) = $self->_fetch_empty_plate_by_attribute( $statement, $plate_id );
    if( $num_rows == 0 ){
        "Couldn't find plate:$plate_id in database.\n";
    }
    elsif( $num_rows > 1 ){
        "Plate id:$plate_id should be unique, but got more than one row returned!\n";
    }
    else{
        return $plate;
    }
}

=method fetch_empty_plate_by_name

  Usage       : $plate_adaptor->fetch_empty_plate_by_name;
  Purpose     : Stores a plate in the db
  Returns     : Crispr::Plate
  Parameters  : Crispr::Plate
  Throws      : If plate is not supplied
                If supplied parameter is not a Crispr::Plate object
  Comments    : 

=cut

sub fetch_empty_plate_by_name {
    my ( $self, $plate_name ) = @_;
    # statement - fetch plate by id
    my $statement = "select * from plate where plate_name = ?;";
    
    my ( $plate, $num_rows ) = $self->_fetch_empty_plate_by_attribute( $statement, $plate_name );
    if( $num_rows == 0 ){
        "Couldn't find plate:$plate_name in database.\n";
    }
    elsif( $num_rows > 1 ){
        "Plate name:$plate_name should be unique, but got more than one row returned!\n";
    }
    else{
        return $plate;
    }
}

=method _fetch_empty_plate_by_attribute

  Usage       : $plate_adaptor->_fetch_empty_plate_by_attribute;
  Purpose     : Stores a plate in the db
  Returns     : Crispr::Plate
  Parameters  : Crispr::Plate
  Throws      : If plate is not supplied
                If supplied parameter is not a Crispr::Plate object
  Comments    : 

=cut

sub _fetch_empty_plate_by_attribute {
    my ( $self, $fetch_statement, $attribute ) = @_;
    my $dbh = $self->connection->dbh();
    my $plate;
    my $num_rows = 0;
    $self->connection->txn(  fixup => sub {
		my $sth = $dbh->prepare($fetch_statement);
        $sth->execute( $attribute );
        
        while( my @fields = $sth->fetchrow_array ){
            $num_rows++;
            $plate = $self->_make_new_plate_from_db( \@fields );
        }
		$sth->finish();
    } );
	
    return ( $plate, $num_rows );
}

=method fetch_crispr_plate_by_plate_name

  Usage       : $plate_adaptor->fetch_crispr_plate_by_plate_name;
  Purpose     : Stores a plate in the db
  Returns     : Crispr::Plate
  Parameters  : Crispr::Plate
  Throws      : If plate is not supplied
                If supplied parameter is not a Crispr::Plate object
  Comments    : 

=cut

sub fetch_crispr_plate_by_plate_name {
    my ( $self, $plate_name ) = @_;
    
    my $plate = $self->fetch_empty_plate_by_name( $plate_name );
    
    my $select_statement = join(q{ },
        'select * from crRNA c, plate pl',
        'where pl.plate_name = ? and c.plate_id = pl.plate_id;'
    );
    
    my $results = $self->fetch_rows_for_generic_select_statement( $select_statement, [ $plate_name ] );
    
    foreach my $row ( @{$results} ){
        my $crRNA = $self->crRNA_adaptor->_make_new_crRNA_from_db( [ @{$row}[0..7] ] );
        # TO DO: add fetching off-target_info and coding scores
        $plate->fill_well( $crRNA, $row->[13] );
    }
    
    return $plate;
}

=method fetch_primer_pair_plate_by_plate_name

  Usage       : $plate_adaptor->fetch_primer_pair_plate_by_plate_name;
  Purpose     : Stores a plate in the db
  Returns     : Crispr::Plate
  Parameters  : Crispr::Plate
  Throws      : If plate is not supplied
                If supplied parameter is not a Crispr::Plate object
  Comments    : 

=cut

sub fetch_primer_pair_plate_by_plate_name {
    my ( $self, $plate_name ) = @_;
    
    my $plate = $self->fetch_empty_plate_by_name( $plate_name );
    
    my $select_statement = join(q{ },
        'select * from plate pl, primer p1, primer p2, primer_pair pp',
        'where plate_name = ? and',
        'pl.plate_id = p1.plate_id and pl.plate_id = p2.plate_id and',
        'p1.primer_id = pp.left_primer_id and p2.primer_id = pp.right_primer_id;' );
    
    my $results;
    
    eval{
        $results = $self->fetch_rows_for_generic_select_statement(
                                    $select_statement, [ $plate_name ] );
    };
    if( $EVAL_ERROR ){
        if( $EVAL_ERROR =~ m/NO\sROWS/xms ){
            die join(q{ }, "Plate", $plate_name, "does not exist in the database or is empty!\n" );
        }
    }
    
    foreach my $row ( @{$results} ){
        my $primer_pair = $self->primer_pair_adaptor->_make_new_primer_pair_from_db( [ @{$row}[6..32] ] );
        $plate->fill_well( $primer_pair, $row->[14] );
    }
    
    return $plate;
}

#_fetch
#
#Usage       : $plate = $self->_fetch( $where_clause, $where_parameters );
#Purpose     : Fetch Plate objects from the database with arbitrary parameteres
#Returns     : ArrayRef of Crispr::DB::Plate objects
#Parameters  : where_clause => Str (SQL where clause)
#               where_parameters => ArrayRef of parameters to bind to sql statement
#Throws      : 
#Comments    : 

my %plate_cache;
sub _fetch {
    my ( $self, $where_clause, $where_parameters ) = @_;
    my $dbh = $self->connection->dbh();
    
    my $sql = <<'END_SQL';
        SELECT
			plate_id,
			plate_name,
			plate_type,
			plate_category,
			ordered,
			received
        FROM plate
END_SQL

    if ($where_clause) {
        $sql .= 'WHERE ' . $where_clause;
    }

    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $plate_id, $plate_name, $plate_type, $plate_category,
        $ordered, $received );
    
    $sth->bind_columns( \( $plate_id, $plate_name, $plate_type,
                          $plate_category, $ordered, $received, ) );

    my @plates = ();
    while ( $sth->fetch ) {
        my $plate;
        if( !exists $plate_cache{ $plate_id } ){
            my $plate = Crispr::Plate->new(
                                            plate_id => $plate_id,
                                            plate_name => $plate_name,
                                            plate_type => $plate_type,
                                            plate_category => $plate_category,
                                            ordered => $ordered,
                                            received => $received,
                                        );
            $plate_cache{ $plate_id } = $plate;
        }
        else{
            $plate = $plate_cache{ $plate_id };
        }
        push @plates, $plate;
    }

    return \@plates;    
}

=method _make_new_plate_from_db

  Usage       : $crRNA_adaptor->_make_new_plate_from_db;
  Purpose     : Stores a plate in the db
  Returns     : Crispr::Plate
  Parameters  : Crispr::Plate
  Throws      : If plate is not supplied
                If supplied parameter is not a Crispr::Plate object
  Comments    : 

=cut

sub _make_new_plate_from_db {
    my ( $self, $fields, $category ) = @_;
    
    my $plate = Crispr::Plate->new(
        plate_id => $fields->[0],
        plate_name => $fields->[1],
        plate_type => $fields->[2],
		plate_category => $fields->[3],
        ordered => $fields->[4],
        received => $fields->[5],
    );
	
	if( $category ){
		$plate->plate_category( $category );
	}
    return $plate;
}

__PACKAGE__->meta->make_immutable;
1;
