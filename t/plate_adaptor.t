#!/usr/bin/env perl
# target_adaptor.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::DatabaseRow;
use Test::MockObject;
use Data::Dumper;
use Readonly;

use Crispr::DB::PlateAdaptor;

Readonly my $TESTS_IN_COMMON => 1 + 15 + 4 + 3 + 1 + 5 + 5 + 5 + 3;
Readonly my %TESTS_FOREACH_DBC => (
    mysql => $TESTS_IN_COMMON,
    sqlite => $TESTS_IN_COMMON,
);
plan tests => $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite};

use DateTime;
#get current date
my $date_obj = DateTime->now();
my $todays_date = $date_obj->ymd;

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
# TestDB creates test database, connects to it and gets db handle
my @db_connections;
foreach my $driver ( keys %db_connection_params ){
    push @db_connections, TestDB->new( $db_connection_params{$driver} );
}

SKIP: {
    skip 'No database connections available', $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite} if !@db_connections;
    
    if( @db_connections == 1 ){
        skip 'Only one database connection available', $TESTS_FOREACH_DBC{sqlite} if $db_connections[0]->driver eq 'mysql';
        skip 'Only one database connection available', $TESTS_FOREACH_DBC{mysql} if $db_connections[0]->driver eq 'sqlite';
    }
}

foreach my $db_connection ( @db_connections ){
    my $driver = $db_connection->driver;
    my $dbh = $db_connection->connection->dbh;
    # $dbh is a DBI database handle
    local $Test::DatabaseRow::dbh = $dbh;
    
    # make a mock DBConnection object
    my $mock_db_connection = Test::MockObject->new();
    $mock_db_connection->set_isa( 'Crispr::DB::DBConnection' );
    $mock_db_connection->mock( 'dbname', sub { return $db_connection->dbname } );
    $mock_db_connection->mock( 'connection', sub { return $db_connection->connection } );
    
    # make a new real Plate Adaptor
    my $plate_ad = Crispr::DB::PlateAdaptor->new( db_connection => $mock_db_connection );
    # 1 test
    isa_ok( $plate_ad, 'Crispr::DB::PlateAdaptor' );
    
    # check methods 15 tests
    my @methods = qw( dbname db_connection connection check_entry_exists_in_db fetch_rows_expecting_single_row
        fetch_rows_for_generic_select_statement _db_error_handling store get_plate_id_from_name fetch_empty_plate_by_id
        fetch_empty_plate_by_name _fetch_empty_plate_by_attribute fetch_crispr_plate_by_plate_name _make_new_plate_from_db _build_crRNA_adaptor
    );
    
    foreach my $method ( @methods ) {
        can_ok( $plate_ad, $method );
    }
    
    # Should have used a mock object for this really, change sometime
    use Crispr::Plate;
    
    # make a new fully specified plate
    my $plate_1 = Crispr::Plate->new(
        id => '1',
        plate_name => 'CR-000001a',
        plate_type => '96',
        plate_category => 'construction_oligos',
        ordered => $date_obj,
        received => $date_obj,
    );
    
    # make a new plate with only name specified
    my $plate_2 = Crispr::Plate->new(
        plate_name => 'CR-000001b',
        plate_category => 'pcr_primers',
    );
    
    my $plate_3 = Crispr::Plate->new(
        plate_name => 'CR-000002a',
        plate_type => '384',
        plate_category => 'expression_construct',
    );
    
    # store target
    $plate_1 = $plate_ad->store($plate_1);
    $plate_2 = $plate_ad->store($plate_2);
    $plate_3 = $plate_ad->store($plate_3);
    
    # check plate id - 4 tests
    is( $plate_1->plate_id, 1, 'Check primary key' );
    is( $plate_2->plate_id, 2, 'Check primary key' );
    is( $plate_3->plate_id, 3, 'Check primary key' );
    throws_ok { $plate_ad->store($plate_3) } qr/PLATE\sALREADY\sEXISTS/, 'Check throws correctly if plate already exists in db.';
    
    # check database row
    # 3 tests
    row_ok(
       table => 'plate',
       where => [ plate_id => 1 ],
       tests => {
           'eq' => {
                plate_name => 'CR-000001a',
                plate_type => '96',
                ordered  => $todays_date,
                received => $todays_date,
                plate_category => 'construction_oligos',
           },
       },
       label => 'Plate 1 stored',
    );
    
    row_ok(
       table => 'plate',
       where => [ plate_id => 2 ],
       tests => {
           'eq' => {
                plate_name => 'CR-000001b',
                plate_type => '96',
                ordered  => undef,
                received => undef,
                plate_category => 'pcr_primers',
           },
       },
       label => 'Plate 2 stored',
    );
    
    row_ok(
       table => 'plate',
       where => [ plate_id => 3 ],
       tests => {
           'eq' => {
                plate_name => 'CR-000002a',
                plate_type => '384',
                ordered  => undef,
                received => undef,
                plate_category => 'expression_construct',
           },
       },
       label => 'Plate 3 stored',
    );
    
    my $plate_4 = Crispr::Plate->new(
    );
    
    throws_ok { $plate_ad->store($plate_4) } qr/Plate\smust\shave\sa\splate_name/, 'No plate name';
    
    # fetch empty plates by id from database
    my $plate_5 = $plate_ad->fetch_empty_plate_by_id( 1 );
    # 5 tests
    is( $plate_5->plate_id, 1, 'Get id 1' );
    is( $plate_5->plate_name, 'CR-000001a', 'Get plate name 1' );
    is( $plate_5->plate_type, '96', 'Get plate type 1' );
    is( $plate_5->ordered, $todays_date, 'Get ordered 1' );
    is( $plate_5->received, $todays_date, 'Get received 1' );
    
    my $plate_6 = $plate_ad->fetch_empty_plate_by_id( 3 );
    # 5 tests
    is( $plate_6->plate_id, 3, 'Get id 3' );
    is( $plate_6->plate_name, 'CR-000002a', 'Get plate name 3' );
    is( $plate_6->plate_type, '384', 'Get plate type 3' );
    is( $plate_6->ordered, undef, 'Get ordered 3' );
    is( $plate_6->received, undef, 'Get received 3' );
    
    # fetch empty plate by name from database
    my $plate_7 = $plate_ad->fetch_empty_plate_by_name( 'CR-000001a' );
    # 5 tests
    is( $plate_7->plate_id, 1, 'Get id 1' );
    is( $plate_7->plate_name, 'CR-000001a', 'Get plate name 1' );
    is( $plate_7->plate_type, '96', 'Get plate type 1' );
    is( $plate_7->ordered, $todays_date, 'Get ordered 1' );
    is( $plate_7->received, $todays_date, 'Get received 1' );
    
    # check getting id using plate_name - 3 tests
    is( $plate_ad->get_plate_id_from_name( 'CR-000001a' ), 1, 'fetch id from plate_name - 1');
    is( $plate_ad->get_plate_id_from_name( 'CR-000001b' ), 2, 'fetch id from plate_name - 1');
    is( $plate_ad->get_plate_id_from_name( 'CR-000002a' ), 3, 'fetch id from plate_name - 1');
}

# drop databases
foreach ( @db_adaptors ){
    $_->destroy();
}
