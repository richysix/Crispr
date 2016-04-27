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

# cache for plate objects from db
has '_plate_cache' => (
	is => 'ro',
	isa => 'HashRef',
    init_arg => undef,
    writer => '_set_plate_cache',
    default => sub { return {}; },
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
    
    # where clause
    my $where_clause = 'plate_id = ?';
    my $plates = $self->_fetch( $where_clause, [ $plate_id ] );
    return $plates->[0];
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
    
    # where clause
    my $where_clause = 'plate_name = ?';
    my $plates = $self->_fetch( $where_clause, [ $plate_name ] );
    return $plates->[0];
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
    if( !defined $plate ){
        die "Plate $plate_name does not exist in the database!\n";
    }
    
    my $sql = <<'END_SQL';
SELECT p1.primer_id, p1.primer_sequence, p1.primer_chr, p1.primer_start, p1.primer_end,
p1.primer_strand, p1.primer_tail, p1.well_id,
p2.primer_id, p2.primer_sequence, p2.primer_chr, p2.primer_start, p2.primer_end,
p2.primer_strand, p2.primer_tail, p2.well_id,
primer_pair_id, type, chr, start, end, strand, product_size
FROM plate pl, primer p1, primer p2, primer_pair pp
WHERE pl.plate_id = p1.plate_id and pl.plate_id = p2.plate_id AND
p1.primer_id = pp.left_primer_id and p2.primer_id = pp.right_primer_id
END_SQL
    
    my $where_clause = "plate_name = ?";
    my $where_parameters = [ $plate_name, ];
    $sql .= 'AND ' . $where_clause;
    
    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $left_primer_id, $left_primer_sequence, $left_primer_chr,
        $left_primer_start, $left_primer_end, $left_primer_strand,
        $left_primer_tail, $left_well_id,
        $right_primer_id, $right_primer_sequence, $right_primer_chr,
        $right_primer_start, $right_primer_end, $right_primer_strand,
        $right_primer_tail, $right_well_id,
        $primer_pair_id, $type, $chr, $start, $end, $strand, $product_size, );
    
    $sth->bind_columns( \( $left_primer_id, $left_primer_sequence, $left_primer_chr,
        $left_primer_start, $left_primer_end, $left_primer_strand,
        $left_primer_tail, $left_well_id,
        $right_primer_id, $right_primer_sequence, $right_primer_chr,
        $right_primer_start, $right_primer_end, $right_primer_strand,
        $right_primer_tail, $right_well_id,
        $primer_pair_id, $type, $chr, $start, $end, $strand, $product_size, ) );

    while ( $sth->fetch ) {
        
        my $left_primer_seq = defined $left_primer_tail ?
            $left_primer_tail . $left_primer_sequence : $left_primer_sequence;
        my $left_primer = Crispr::Primer->new(
            primer_id => $left_primer_id,
            sequence => $left_primer_seq,
            seq_region => $left_primer_chr,
            seq_region_start => $left_primer_start,
            seq_region_end => $left_primer_end,
            seq_region_strand => $left_primer_strand,
        );
        my $right_primer_seq = defined $right_primer_tail ?
            $right_primer_tail . $right_primer_sequence : $right_primer_sequence;
        my $right_primer = Crispr::Primer->new(
            primer_id => $right_primer_id,
            sequence => $right_primer_seq,
            seq_region => $right_primer_chr,
            seq_region_start => $right_primer_start,
            seq_region_end => $right_primer_end,
            seq_region_strand => $right_primer_strand,
        );
        
        if( $left_well_id ne $right_well_id ){
            # add primers separately
            $plate->fill_well( $left_primer, $left_well_id, );
            $plate->fill_well( $right_primer, $right_well_id, );
        }
        else{
            # make a primer pair and add it to well
            my $pair_name;
            if( defined $chr ){
                $pair_name .= $chr . ":";
            }
            $pair_name .= join("-", $start, $end, );
            if( defined $strand, ){
                $pair_name .= ":" . $strand;
            }
            my $primer_pair = Crispr::PrimerPair->new(
                primer_pair_id => $primer_pair_id,
                type => $type,
                pair_name => $pair_name,
                product_size => $product_size,
                left_primer => $left_primer,
                right_primer => $right_primer,
            );
            $plate->fill_well( $primer_pair, $left_well_id );
        }
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
        if( !exists $self->_plate_cache->{ $plate_id } ){
            $plate = Crispr::Plate->new(
                    plate_id => $plate_id,
                    plate_name => $plate_name,
                    plate_type => $plate_type,
                    plate_category => $plate_category,
                    ordered => $ordered,
                    received => $received,
                );
            my $plate_cache_ref = $self->_plate_cache;
            $plate_cache_ref->{ $plate_id } = $plate;
            $self->_set_plate_cache( $plate_cache_ref );
        }
        else{
            $plate = $self->_plate_cache->{ $plate_id };
        }
        push @plates, $plate;
    }

    return \@plates;    
}

sub _build_plate_cache {
    my ( $self, ) = @_;
    return {};
}

__PACKAGE__->meta->make_immutable;
1;
