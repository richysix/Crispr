#!/usr/bin/env perl
# primer_pair_adaptor.t
use warnings; use strict;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::DatabaseRow;
use Test::MockObject;
use Data::Dumper;
use autodie qw(:all);
use Getopt::Long;
use Readonly;
use File::Spec;

Readonly my $TESTS_FOREACH_DBC => 1 + 13 + 9 + 22 + 22;
plan tests => 2 * $TESTS_FOREACH_DBC;

use Crispr::DB::DBConnection;
use Crispr::DB::PrimerPairAdaptor;
use Crispr::DB::TargetAdaptor;
use Crispr::DB::crRNAAdaptor;
use Crispr::DB::PlateAdaptor;
use Crispr::DB::PrimerAdaptor;

##  database tests  ##
# Module with a function for creating an empty test database
# and returning a database connection
use TestDB;
# check environment variables have been set
if( !$ENV{MYSQL_DBNAME} || !$ENV{MYSQL_DBUSER} || !$ENV{MYSQL_DBPASS} ){
    die "The following environment variables need to be set for connecting to the database!\n",
        "MYSQL_DBNAME, MYSQL_DBUSER, MYSQL_DBPASS"; 
}

my %db_connection_params = (
    mysql => {
        driver => 'mysql',
        dbname => $ENV{MYSQL_DBNAME},
        host => $ENV{MYSQL_DBHOST} || '127.0.0.1',
        port => $ENV{MYSQL_DBPORT} || 3306,
        user => $ENV{MYSQL_DBUSER},
        pass => $ENV{MYSQL_DBPASS},
    },
    sqlite => {
        driver => 'sqlite',
        dbfile => 'test.db',
        dbname => 'test',
    }
);

# TestDB creates test database, connects to it and gets db handle
my %test_db_connections;
foreach my $driver ( keys %db_connection_params ){
    $test_db_connections{$driver} = TestDB->new( $db_connection_params{$driver} );
}

# make a proper DB_Connection
my @db_connections;
foreach my $driver ( keys %db_connection_params ){
    push @db_connections, Crispr::DB::DBConnection->new( $db_connection_params{$driver} );
}


SKIP: {
    skip 'No database connections available', $TESTS_FOREACH_DBC * 2 if !@db_connections;
    skip 'Only one database connection available', $TESTS_FOREACH_DBC
      if @db_connections == 1;
}

Readonly my @rows => ( qw{ A B C D E F G H } );
Readonly my @cols => ( qw{ 01 02 03 04 05 06 07 08 09 10 11 12 } );

foreach my $db_connection ( @db_connections ){
    my $driver = $db_connection->driver;
    my $dbh = $db_connection->connection->dbh;
    
    # $dbh is a DBI database handle
    local $Test::DatabaseRow::dbh = $dbh;
    
    my $primer_pair_ad = Crispr::DB::PrimerPairAdaptor->new( db_connection => $db_connection, );

    # 1 test
    isa_ok( $primer_pair_ad, 'Crispr::DB::PrimerPairAdaptor' );
    
    # check attributes and methods exist 3 + 10 tests
    my @attributes = ( qw{ dbname db_connection connection } );
    
    my @methods = (
        qw{ store fetch_all_by_crRNA fetch_all_by_crRNA_id _fetch _make_new_primer_pair_from_db
        _build_plate_adaptor check_entry_exists_in_db fetch_rows_expecting_single_row fetch_rows_for_generic_select_statement _db_error_handling }
    );

    foreach my $attribute ( @attributes ) {
        can_ok( $primer_pair_ad, $attribute );
    }
    foreach my $method ( @methods ) {
        can_ok( $primer_pair_ad, $method );
    }
    
    # add target info directly to db 
    my $statement = "insert into target values( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    my $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'test_target', 'Zv9', '4', 1, 200, '1', 'zebrafish', 'y', 'GENE0001', 'gene001', 'crispr_test', 75, '2014-10-13');
    
    # plate
    my $mock_plate = Test::MockObject->new();
    $mock_plate->set_isa('Crispr::Plate');
    $mock_plate->mock('plate_id', sub{ return 1 } );
    $mock_plate->mock('plate_name', sub{ return 'CR_000001d' } );
    $mock_plate->mock('plate_category', sub{ return 'pcr_primers' } );
    $mock_plate->mock('plate_type', sub{ return '96' } );
    $mock_plate->mock('ordered', sub{ return undef } );
    $mock_plate->mock('received', sub{ return undef } );
    $statement = "insert into plate values( ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( $mock_plate->plate_id, $mock_plate->plate_name,
        $mock_plate->plate_type, $mock_plate->plate_category,
        $mock_plate->ordered, $mock_plate->received,
    );

    # make a mock crRNA and load it into the db
    my $mock_crRNA = Test::MockObject->new();
    $mock_crRNA->set_isa('Crispr::crRNA');
    $mock_crRNA->mock('crRNA_id', sub{ return 1 } );
    $mock_crRNA->mock('target_id', sub{ '1' } );
    
    $statement = "insert into crRNA values( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( $mock_crRNA->crRNA_id, 'crRNA:5:50383-50405:1', '5',
        50383, 50405, '1',
        'GGAATAGAGAGATAGAGAGTCGG', 0,
        0.853, 1, 0.853,
        $mock_crRNA->target_id, 1, 'A01',
    );
    
    my ( $l_p_id, $r_p_id, $pair_id ) = ( -1, 0, 0 );
    my ( $mock_p1, $mock_p2, $mock_pp );
    
    # make mock well object
    my $well_id ='A01';
    my $mock_well = Test::MockObject->new();
    $mock_well->set_isa('Labware::Well');
    $mock_well->mock('plate', sub { return $mock_plate } );
    $mock_well->mock('position', sub { return $well_id } );
    
    # make mock primer and primer pair objects
    my $mock_left_primer = Test::MockObject->new();
    $l_p_id += 2;
    $mock_left_primer->mock( 'sequence', sub { return 'CGACAGTAGACAGTTAGACGAG' } );
    $mock_left_primer->mock( 'seq_region', sub { return '5' } );
    $mock_left_primer->mock( 'seq_region_start', sub { return 101 } );
    $mock_left_primer->mock( 'seq_region_end', sub { return 124 } );
    $mock_left_primer->mock( 'seq_region_strand', sub { return '1' } );
    $mock_left_primer->mock( 'tail', sub { return undef } );
    $mock_left_primer->set_isa('Crispr::Primer');
    $mock_left_primer->mock('primer_id', sub { my @args = @_; if( $_[1]){ return $_[1] }else{ return $l_p_id} } );
    $mock_left_primer->mock( 'primer_name', sub { return '5:101-124:1' } );
    $mock_left_primer->mock( 'well_id', sub { return 'A01' } );
    $mock_p1 = $mock_left_primer;
    
    my $mock_right_primer = Test::MockObject->new();
    $r_p_id += 2;
    $mock_right_primer->mock( 'sequence', sub { return 'GATAGATACGATAGATGGGAC' } );
    $mock_right_primer->mock( 'seq_region', sub { return '5' } );
    $mock_right_primer->mock( 'seq_region_start', sub { return 600 } );
    $mock_right_primer->mock( 'seq_region_end', sub { return 623 } );
    $mock_right_primer->mock( 'seq_region_strand', sub { return '-1' } );
    $mock_right_primer->mock( 'tail', sub { return undef } );
    $mock_right_primer->set_isa('Crispr::Primer');
    $mock_right_primer->mock('primer_id', sub { my @args = @_; if( $_[1]){ return $_[1] }else{ return $r_p_id} } );
    $mock_right_primer->mock( 'primer_name', sub { return '5:600-623:-1' } );
    $mock_right_primer->mock( 'well_id', sub { return 'A01' } );
    $mock_p2 = $mock_right_primer;
        
    my $mock_primer_pair = Test::MockObject->new();
    $pair_id++;
    $mock_primer_pair->mock( 'type', sub{ return 'ext' } );
    $mock_primer_pair->mock( 'left_primer', sub{ return $mock_left_primer } );
    $mock_primer_pair->mock( 'right_primer', sub{ return $mock_right_primer } );
    $mock_primer_pair->mock( 'seq_region', sub{ return $mock_left_primer->seq_region } );
    $mock_primer_pair->mock( 'seq_region_start', sub{ return $mock_left_primer->seq_region_start } );
    $mock_primer_pair->mock( 'seq_region_end', sub{ return $mock_right_primer->seq_region_end } );
    $mock_primer_pair->mock( 'seq_region_strand', sub{ return 1 } );
    $mock_primer_pair->mock( 'product_size', sub{ return 523 } );
    $mock_primer_pair->set_isa('Crispr::PrimerPair');
    $mock_primer_pair->mock('primer_pair_id', sub { my @args = @_; if($_[1]){ return $_[1] }else{ return $pair_id} } );
    $mock_pp = $mock_primer_pair;
    
    # Test store method - 9 tests
    throws_ok{ $primer_pair_ad->store( $mock_primer_pair, [ $mock_crRNA ] ) }
        qr/Couldn't locate primer/, 'Try storing primer pair before primers are stored';
    
    # store primers
    $statement = "insert into primer values( ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    foreach my $p ( $mock_left_primer, $mock_right_primer ){
        $sth->execute( $p->primer_id, $p->sequence, $p->seq_region,
            $p->seq_region_start, $p->seq_region_end, $p->seq_region_strand,
            $p->tail, 1, $p->well_id,
        );
    }
    
    # now store primer pair info
    $primer_pair_ad->store( $mock_primer_pair, [ $mock_crRNA ] );
    
    # check database rows
    row_ok(
        sql => "SELECT * FROM primer_pair WHERE primer_pair_id = 1",
        tests => {
            'eq' => {
                 type  => $mock_primer_pair->type,
            },
            '==' => {
                 left_primer_id    => $mock_left_primer->primer_id,
                 right_primer_id    => $mock_right_primer->primer_id,
                 product_size => $mock_primer_pair->product_size,
            },
        },
        label => "primer pair stored - 1",
    );
    row_ok(
        sql => "SELECT * FROM amplicon_to_crRNA WHERE primer_pair_id = 1",
        tests => {
            '==' => {
                 crRNA_id  => 1,
            },
        },
        label => "primer pair to crRNA table - 1",
    );
    
    throws_ok{ $primer_pair_ad->store( undef ) }
        qr/primer_pair must be supplied in order to add oligos to the database/, 'calling store with undef primer pair';
    throws_ok{ $primer_pair_ad->store( 'primer' ) }
        qr/Supplied object must be a Crispr::PrimerPair object/, 'calling store with string';
    throws_ok{ $primer_pair_ad->store( $mock_p1 ) }
        qr/Supplied object must be a Crispr::PrimerPair object/, 'calling store with non PrimerPair object';
    throws_ok{ $primer_pair_ad->store( $mock_pp, ) }
        qr/At least one crRNA_id must be supplied in order to add oligos to the database/, 'calling store without any crRNA ids';
    throws_ok{ $primer_pair_ad->store( $mock_pp, 'primer' ) }
        qr/crRNA_ids must be supplied as an ArrayRef/, 'calling store with string as crRNA ids';
    throws_ok{ $primer_pair_ad->store( $mock_pp, [ $mock_pp ] ) }
        qr/Supplied object must be a Crispr::crRNA object/, 'calling store with crRNA ids in empty ArrayRef';
    
    # test fetch methods
    # _fetch - 22 tests
    my $where_clause = 'pp.primer_pair_id = ?';
    my $primer_pair_from_db;
    ok( $primer_pair_from_db = $primer_pair_ad->_fetch( $where_clause, [ 1 ] ), 'Test _fetch method' );
    check_primer_pair_attributes( $primer_pair_from_db->[0], $mock_primer_pair, $driver, '_fetch' );
    
    # fetch_by_plate_and_well - 22 tests
    ok( $primer_pair_from_db = $primer_pair_ad->fetch_by_plate_name_and_well( $mock_plate->plate_name, 'A01' ), 'Test fetch_by_plate_name_and_well method' );
    SKIP: {
        skip 'No primer pair returned from db', 1 if !defined $primer_pair_from_db;
        
        check_primer_pair_attributes( $primer_pair_from_db, $mock_primer_pair, $driver, 'fetch_by_plate_name_and_well' );
    }
}

# drop databases
foreach my $driver ( keys %test_db_connections ){
    $test_db_connections{$driver}->destroy();
}

# 5 + 16 tests per call
sub check_primer_pair_attributes {
    my ( $obj_1, $obj_2, $driver, $method, ) = @_;
    is( $obj_1->primer_pair_id, $obj_2->primer_pair_id, "$driver: object from db $method - check primer pair db_id" );
    is( $obj_1->seq_region, $obj_2->seq_region, "$driver: object from db $method - check chr" );
    is( $obj_1->seq_region_start, $obj_2->seq_region_start, "$driver: object from db $method - check start" );
    is( $obj_1->seq_region_end, $obj_2->seq_region_end, "$driver: object from db $method - check end" );
    is( $obj_1->seq_region_strand, $obj_2->seq_region_strand, "$driver: object from db $method - check strand" );
    
    check_primer_attributes( $obj_1->left_primer, $obj_2->left_primer, $driver, $method, );
    check_primer_attributes( $obj_1->right_primer, $obj_2->right_primer, $driver, $method, );
}

sub check_primer_attributes {
    my ( $obj_1, $obj_2, $driver, $method, ) = @_;
    my $seq = $obj_2->tail
        ? $obj_2->tail . $obj_2->sequence
        : $obj_2->sequence;
    is( $obj_1->sequence, $seq, "$driver: object from db $method - check primer seq" );
    is( $obj_1->primer_id, $obj_2->primer_id, "$driver: object from db $method - check primer id" );
    is( $obj_1->seq_region, $obj_2->seq_region, "$driver: object from db $method - check primer chr" );
    is( $obj_1->seq_region_start, $obj_2->seq_region_start, "$driver: object from db $method - check primer start" );
    is( $obj_1->seq_region_end, $obj_2->seq_region_end, "$driver: object from db $method - check primer end" );
    is( $obj_1->seq_region_strand, $obj_2->seq_region_strand, "$driver: object from db $method - check primer strand" );
    is( $obj_1->primer_name, $obj_2->primer_name, "$driver: object from db $method - check primer name" );
    is( $obj_1->well_id, $obj_2->well_id, "$driver: object from db $method - check primer well id" );
}
