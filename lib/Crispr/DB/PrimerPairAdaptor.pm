## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::PrimerPairAdaptor;
## use critic

# ABSTRACT: PrimerPairAdaptor object - object for storing PrimerPair objects in and retrieving them from a SQL database

use namespace::autoclean;
use Moose;
use English qw( -no_match_vars );
use DateTime;
use Readonly;
use Crispr::Primer;
use Crispr::PrimerPair;

extends 'Crispr::DB::BaseAdaptor';

# Cache for primer_pairs. HashRef keyed on db_id
my %primer_pair_cache;

=method new

  Usage       : my $primer_adaptor = Crispr::DB::PrimerPairAdaptor->new(
					db_connection => $db_connection,
                );
  Purpose     : Constructor for creating primer adaptor objects
  Returns     : Crispr::DB::PrimerPairAdaptor object
  Parameters  :     db_connection => Crispr::DB::DBConnection object,
  Throws      : If parameters are not the correct type
  Comments    : The preferred method for constructing a PrimerAdaptor is to use the
                get_adaptor method with a previously constructed DBConnection object

=cut

=method plate_adaptor

  Usage       : $primer_adaptor->plate_adaptor;
  Purpose     : Getter for a plate_adaptor
  Returns     : Crispr::DB::PlateAdaptor
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'plate_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::PlateAdaptor',
    lazy => 1,
    builder => '_build_plate_adaptor',
);

=method primer_adaptor

  Usage       : $primer_adaptor->primer_adaptor;
  Purpose     : Getter for a primer_adaptor
  Returns     : Crispr::DB::PlateAdaptor
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'primer_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::PrimerAdaptor',
    lazy => 1,
    builder => '_build_primer_adaptor',
);

my $date_obj = DateTime->now();
Readonly my $PLATE_TYPE => '96';

=method store

  Usage       : $primer_pair_adaptor->store;
  Purpose     : method to store a primer_pair in the database.
  Returns     : 1 on Success.
  Parameters  : Crispr::PrimerPair
                Crispr::crRNA
  Throws      : If input is not correct type
  Comments    : 

=cut

sub store {
    # Primers must have already been added to the db
    my ( $self, $primer_pair, $crRNAs ) = @_;
    my $dbh = $self->connection->dbh();
    
    if( !$primer_pair ){
        confess "primer_pair must be supplied in order to add oligos to the database!\n";
    }
    if( !ref $primer_pair || !$primer_pair->isa('Crispr::PrimerPair') ){
        confess "Supplied object must be a Crispr::PrimerPair object, not ", ref $primer_pair, ".\n";
    }
    if( !$crRNAs ){
        confess "At least one crRNA_id must be supplied in order to add oligos to the database!\n";
    }
    elsif( ref $crRNAs ne 'ARRAY' ){
        confess "crRNA_ids must be supplied as an ArrayRef!\n";
    }
    foreach ( @{$crRNAs} ){
        if( !ref $_ || !$_->isa('Crispr::crRNA') ){
            confess "Supplied object must be a Crispr::crRNA object, not ", ref $_, ".\n";
        }
    }
    # statement to check primers exist in db
    my $check_primer_st = "select count(*) from primer where primer_id = ?;";
    # statement to add pair into primer_pair table
    my $pair_statement = "insert into primer_pair values( ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    my $pair_to_crRNA_statement = "insert into amplicon_to_crRNA values( ?, ? );";
    
    $self->connection->txn(  fixup => sub {
        # check whether primers already exist in database
        foreach my $primer ( $primer_pair->left_primer, $primer_pair->right_primer ){
            if( !$self->check_entry_exists_in_db( $check_primer_st, [ $primer->primer_id ] ) ){
                confess "Couldn't locate primer, ", $primer_pair->left_primer->primer_name, "in the database!\n",
                "Primers must be added to database before primer pair info.\n";
            }
        }
        
        # add primer pair info
        my $sth = $dbh->prepare($pair_statement);
        $sth->execute(
            undef,
            $primer_pair->type,
            $primer_pair->left_primer->primer_id,
            $primer_pair->right_primer->primer_id,
            $primer_pair->seq_region,
            $primer_pair->seq_region_start,
            $primer_pair->seq_region_end,
            $primer_pair->seq_region_strand,
            $primer_pair->product_size,
        );
        my $last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'primer_pair', 'primer_pair_id' );
        $primer_pair->primer_pair_id( $last_id );
        
        $sth = $dbh->prepare($pair_to_crRNA_statement);
        foreach my $crRNA ( @{$crRNAs} ){
            $sth->execute(
                $last_id,
                $crRNA->crRNA_id,
            );
        }
        $sth->finish();
    } );
    return 1;
}

=method fetch_all_by_crRNA

  Usage       : $primer_pair_adaptor->fetch_all_by_crRNA( $crRNA );
  Purpose     : method to retrieve primer pairs for a crRNA using it's db id.
  Returns     : Crispr::PrimerPair
  Parameters  : Crispr::crRNA
  Throws      : If input is not correct type
  Comments    : 

=cut

sub fetch_all_by_crRNA {
    my ( $self, $crRNA, ) = @_;
    my $where_clause = 'amp.crRNA_id = ?';
    my $primer_pairs = $self->_fetch( $where_clause, [ $crRNA->crRNA_id ], );
    return $primer_pairs;
}

=method fetch_all_by_crRNA_id

  Usage       : $primer_pair_adaptor->fetch_all_by_crRNA_id( '1' );
  Purpose     : method to retrieve primer pairs for a crRNA using it's db id.
  Returns     : Crispr::PrimerPair
  Parameters  : Str (crRNA db id)
  Throws      : If input is not correct type
  Comments    : 

=cut

sub fetch_all_by_crRNA_id {
    my ( $self, $crRNA_id, ) = @_;
    my $where_clause = 'amp.crRNA_id = ?';
    my $primer_pairs = $self->_fetch( $where_clause, [ $crRNA_id ], );
    return $primer_pairs;
}

=method fetch_by_id

  Usage       : $primer_pair_adaptor->fetch_by_id( '1' );
  Purpose     : method to retrieve a primer pair using it's db id.
  Returns     : Crispr::PrimerPair
  Parameters  : Str (primer pair db id)
  Throws      : If input is not correct type
  Comments    : 

=cut

sub fetch_by_id {
    my ( $self, $primer_pair_id, ) = @_;
    my $where_clause = 'pp.primer_pair_id = ?';
    my $primer_pairs = $self->_fetch( $where_clause, [ $primer_pair_id ], );
    return $primer_pairs->[0];
}

=method fetch_by_plate_name_and_well

  Usage       : $primer_pair_adaptor->fetch_by_plate_name_and_well( 'CR_000001g', 'A01' );
  Purpose     : method to retrieve a primer pair using a plate name and well id
  Returns     : Crispr::PrimerPair
  Parameters  : Str (plate name)
                Str (well id)
  Throws      : 
  Comments    : returns undef if no primer pair object is returned form the database

=cut

sub fetch_by_plate_name_and_well {
    my ( $self, $plate_name, $well_id, ) = @_;
    my $primer_pair;
    
    my $sql = <<"END_SQL";
SELECT pp.primer_pair_id, type, left_primer_id, right_primer_id,
pp.chr, pp.start, pp.end, pp.strand, pp.product_size,
p1.primer_id, p1.primer_sequence, p1.primer_chr, p1.primer_start, p1.primer_end,
p1.primer_strand, p1.primer_tail, p1.plate_id, p1.well_id
FROM primer_pair pp, primer p1, amplicon_to_crRNA amp, plate pl
WHERE pp.primer_pair_id = amp.primer_pair_id
AND pp.left_primer_id = p1.primer_id
AND pl.plate_id = p1.plate_id
AND pl.plate_name = ? AND p1.well_id = ?;
END_SQL

    my $sth = $self->_prepare_sql(
        $sql,
        'p1.plate_name = ? AND p1.well_id = ?',
        [ $plate_name, $well_id ],
    );
    $sth->execute();
    
    my ( $primer_pair_id, $type, $left_primer_id, $right_primer_id,
        $chr, $start, $end, $strand, $product_size,
        $primer_id, $primer_sequence, $primer_chr, $primer_start, $primer_end,
        $primer_strand, $primer_tail, $plate_id );
    
    $sth->bind_columns( \( $primer_pair_id, $type,
        $left_primer_id, $right_primer_id,
        $chr, $start, $end, $strand, $product_size,
        $primer_id, $primer_sequence, $primer_chr, $primer_start, $primer_end,
        $primer_strand, $primer_tail, $plate_id, $well_id ) );
    
    while ( $sth->fetch ) {
        if( !exists $primer_pair_cache{ $primer_pair_id } ){
            my $primer_sequence = defined $primer_tail
                    ?   $primer_tail . $primer_sequence
                    :   $primer_sequence;
            my $primer_name = join(":", $primer_chr,
                                   join("-", $primer_start, $primer_end, ),
                                   $primer_strand, );
            
            my $left_primer = Crispr::Primer->new(
                primer_id => $left_primer_id,
                plate_id => $plate_id,
                well_id => $well_id,
                sequence => $primer_sequence,
                primer_name => $primer_name,
                seq_region => $primer_chr,
                seq_region_strand => $primer_strand,
                seq_region_start => $primer_start,
                seq_region_end => $primer_end,
            );
            my $right_primer = $self->primer_adaptor->fetch_by_id( $right_primer_id );
            my $pair_name = join(":", $chr, join("-", $start, $end, ), $strand, );
            
            $primer_pair = Crispr::PrimerPair->new(
                primer_pair_id => $primer_pair_id,
                left_primer => $left_primer,
                right_primer => $right_primer,
                pair_name => $pair_name,
                product_size => $product_size,
                type => $type,
            );
            $primer_pair_cache{ $primer_pair_id } = $primer_pair;
        }
        else{
            $primer_pair = $primer_pair_cache{ $primer_pair_id };
        }
    }
    return $primer_pair;
}

=method _fetch

  Usage       : $primer_pair_adaptor->_fetch( $where_clause, $where_params_array );
  Purpose     : internal method for fetching primer_pair from the database.
  Returns     : Crispr::PrimerPair
  Parameters  : Str - Where statement e.g. 'primer_pair_id = ?'
                ArrayRef - Where Parameters. One for each ? in where statement
  Throws      : 
  Comments    : 

=cut

sub _fetch {
    my ( $self, $where_clause, $where_parameters ) = @_;
    my $dbh = $self->connection->dbh();
    
    ## need to change query depending on whether driver is MySQL or SQLite
    #my ( $left_p_concat_statement, $right_p_concat_statement );
    #if( ref $self->connection->driver eq 'DBIx::Connector::Driver::mysql' ){
    #    $left_p_concat_statement = 'concat( p1.primer_tail, p1.primer_sequence )';
    #    $right_p_concat_statement = 'concat( p2.primer_tail, p2.primer_sequence )';
    #}else{
    #    $left_p_concat_statement = 'p1.primer_tail || p1.primer_sequence';
    #    $right_p_concat_statement = 'p2.primer_tail || p2.primer_sequence';
    #}
    
    my $sql = <<"END_SQL";
        SELECT
			pp.primer_pair_id, pp.type, pp.chr,
            pp.start, pp.end, pp.strand, pp.product_size,
            p1.primer_id, p1.primer_tail, p1.primer_sequence,
            p1.primer_chr, p1.primer_start, p1.primer_end, p1.primer_strand,
            p1.plate_id, p1.well_id,
            p2.primer_id, p2.primer_tail, p2.primer_sequence,
            p2.primer_chr, p2.primer_start, p2.primer_end, p2.primer_strand,
            p2.plate_id, p2.well_id
        FROM primer_pair pp, primer p1, primer p2, amplicon_to_crRNA amp
        WHERE left_primer_id = p1.primer_id AND right_primer_id = p2.primer_id
        AND pp.primer_pair_id = amp.primer_pair_id
END_SQL

    if ($where_clause) {
        $sql .= 'AND ' . $where_clause;
    }

    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $primer_pair_id, $type, $chr, $start, $end, $strand, $product_size,
            $left_primer_id, $left_tail, $left_sequence, $left_primer_chr,
            $left_primer_start, $left_primer_end, $left_primer_strand,
            $left_primer_plate_id, $left_primer_well_id,
            $right_primer_id, $right_tail, $right_sequence, $right_primer_chr,
            $right_primer_start, $right_primer_end, $right_primer_strand,
            $right_primer_plate_id, $right_primer_well_id, );
    
    $sth->bind_columns( \( $primer_pair_id, $type, $chr, $start, $end, $strand, $product_size,
            $left_primer_id, $left_tail, $left_sequence, $left_primer_chr,
            $left_primer_start, $left_primer_end, $left_primer_strand,
            $left_primer_plate_id, $left_primer_well_id,
            $right_primer_id, $right_tail, $right_sequence, $right_primer_chr,
            $right_primer_start, $right_primer_end, $right_primer_strand,
            $right_primer_plate_id, $right_primer_well_id, ) );

    my @primer_pairs = ();
    while ( $sth->fetch ) {
        my $primer_pair;
        if( !exists $primer_pair_cache{ $primer_pair_id } ){
            $left_sequence = $left_tail ? $left_tail . $left_sequence
                : $left_sequence;
            my $left_primer = $self->primer_adaptor->_make_new_primer_from_db(
                [ $left_primer_id, $left_sequence, $left_primer_chr,
                    $left_primer_start, $left_primer_end, $left_primer_strand,
                    $left_primer_plate_id, $left_primer_well_id, ]
            );
            $right_sequence = $right_tail ? $right_tail . $right_sequence
                : $right_sequence;
            my $right_primer = $self->primer_adaptor->_make_new_primer_from_db(
                [ $right_primer_id, $right_sequence, $right_primer_chr,
                    $right_primer_start, $right_primer_end, $right_primer_strand,
                    $right_primer_plate_id, $right_primer_well_id, ]
            );
            
            my $pair_name = join(":", $chr, join("-", $start, $end, ), $strand, );
            $primer_pair = Crispr::PrimerPair->new(
                primer_pair_id => $primer_pair_id,
                type => $type,
                pair_name => $pair_name,
                left_primer => $left_primer,
                right_primer => $right_primer,
            );
            $primer_pair_cache{ $primer_pair_id } = $primer_pair;
        }
        else{
            $primer_pair = $primer_pair_cache{ $primer_pair_id };
        }
        
        push @primer_pairs, $primer_pair;
    }

    return \@primer_pairs;    
}

=method _make_new_primer_pair_from_db

  Usage       : $primer_pair_adaptor->_make_new_primer_pair_from_db( $primer_info );
  Purpose     : internal method to make a new PrimerPair from an ArrayRef of fields
  Returns     : Crispr::PrimerPair
  Parameters  : ArrayRef[ Str ] - db info for primer pair
  Throws      : 
  Comments    : 

=cut

sub _make_new_primer_pair_from_db {
    my ( $self, $fields, ) = @_;
    
    my $l_p_seq = defined $fields->[6] ? $fields->[6] . $fields->[1] : $fields->[1];
    my $left_primer = Crispr::Primer->new(
        primer_id => $fields->[0],
        sequence => $l_p_seq,
        seq_region => $fields->[2],
        seq_region_start => $fields->[3],
        seq_region_end => $fields->[4],
        seq_region_strand => $fields->[5],
        plate_id => $fields->[7],
        well => $fields->[8],
    );
    
    my $r_p_seq = defined $fields->[15] ? $fields->[15] . $fields->[10] : $fields->[10];
    my $right_primer = Crispr::Primer->new(
        primer_id => $fields->[9],
        sequence => $r_p_seq,
        seq_region => $fields->[11],
        seq_region_start => $fields->[12],
        seq_region_end => $fields->[13],
        seq_region_strand => $fields->[14],
        plate_id => $fields->[16],
        well => $fields->[17],
    );
    
    my $pair_name;
    if( defined $fields->[22] ){
        $pair_name .= $fields->[22] . ":";
    }
    $pair_name .= join("-", $fields->[23], $fields->[24], );
    if( defined $fields->[25] ){
        $pair_name .= ":" . $fields->[25];
    }
    my $primer_pair = Crispr::PrimerPair->new(
        primer_pair_id => $fields->[18],
        pair_name => $pair_name,
        type => $fields->[19],
        product_size => $fields->[26],
        left_primer => $left_primer,
        right_primer => $right_primer,
    );
    
    return $primer_pair;
}

#_build_plate_adaptor

  #Usage       : $crRNAs = $crRNA_adaptor->_build_plate_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::PlateAdaptor
  #Returns     : Crispr::DB::PlatePrepAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_plate_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'plate' );
}

#_build_primer_adaptor

  #Usage       : $crRNAs = $crRNA_adaptor->_build_primer_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::PlateAdaptor
  #Returns     : Crispr::DB::PlatePrepAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_primer_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'primer' );
}

1;

