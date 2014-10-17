package Crispr::DB::PlateAdaptor;
use namespace::autoclean;
use Moose;
use Crispr::Target;
use Crispr::crRNA;
use Crispr::Plate;
use Carp qw( cluck confess );

extends 'Crispr::DB::BaseAdaptor';

=method crRNA_adaptor

  Usage       : $plate_adaptor->crRNA_adaptor;
  Purpose     : Getter for a crRNA_adaptor
  Returns     : Crispr::DB::crRNAAdaptor
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'crRNA_adaptor' => (
	is => 'ro',
	isa => 'Crispr::DB::crRNAAdaptor',
	lazy => 1,
	builder => '_build_crRNA_adaptor',
);

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
        'select * from plate pl, construction_oligos con, crRNA c',
        'where pl.plate_name = ? and con.plate_id = pl.plate_id and',
        'con.crRNA_id = c.crRNA_id and off.crRNA_id = c.crRNA_id and',
        'cod.crRNA_id = c.crRNA_id limit 5;' );
    
    my $results = $self->fetch_rows_for_generic_select_statement( $select_statement, [ $plate_name ] );
    
    foreach my $row ( @{$results} ){
        my $crRNA = $self->crRNA_adaptor->_make_new_crRNA_from_db( [ @{$row}[12..21] ] );
        # TO DO: add fetching off-target_info and coding scores
        $plate->fill_well( $crRNA, $row->[11] );
    }
    
    return $plate;
}

#_fetch
#
#Usage       : $plate = $self->_fetch( $where_clause, $where_parameters );
#Purpose     : Create a new object from a db entry
#Returns     : Crispr::DB::Cas9Prep object
#Parameters  : ArrayRef of Str
#Throws      : 
#Comments    :

my %plate_cache;
sub _fetch {
    my ( $self, $where_clause, $where_parameters ) = @_;
    my $dbh = $self->connection->dbh();
    
    my $sql = <<'END_SQL';
        SELECT
			plate_id,
			plate_type,
			prep_type,
			made_by,
			date
        FROM plate
END_SQL

    if ($where_clause) {
        $sql .= 'WHERE ' . $where_clause;
    }

    my $sth = $dbh->prepare($sql);

    # Bind any parameters
    if ( ref $where_parameters eq 'ARRAY' ) {
        my $param_num = 0;
        while ( @{$where_parameters} ) {
            $param_num++;
            my $value = shift @{$where_parameters};
            $sth->bind_param( $param_num, $value );
        }
    }

    $sth->execute();

    my ( $plate_id, $plate_type, $prep_type, $made_by, $plate_date,  );
    
    $sth->bind_columns( \( $plate_id, $plate_type, $prep_type, $made_by, $plate_date,  ) );

    my @plates = ();
    while ( $sth->fetch ) {
        my $plate;
        if( !exists $plate_cache{ $plate_id } ){
            my $plate = Crispr::Cas9->new( type => $plate_type );
            $plate = Crispr::DB::Cas9Prep->new(
                db_id => $plate_id,
                plate => $plate,
                prep_type => $prep_type,
                made_by => $made_by,
                date => $plate_date,
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

=method _build_crRNA_adaptor

  Usage       : $crRNA_adaptor->_build_crRNA_adaptor;
  Purpose     : Stores a plate in the db
  Returns     : Crispr::Plate
  Parameters  : Crispr::Plate
  Throws      : If plate is not supplied
                If supplied parameter is not a Crispr::Plate object
  Comments    : 

=cut

sub _build_crRNA_adaptor {
	my ( $self, ) = @_;
	# make a new PlateAdaptor
	my $crRNA_adaptor = Crispr::DB::PlateAdaptor->new( $self->db_params );
	return $crRNA_adaptor;
}

__PACKAGE__->meta->make_immutable;
1;
