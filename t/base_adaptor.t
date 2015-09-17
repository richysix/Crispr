#!/usr/bin/env perl
# base_adaptor.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::DatabaseRow;
use Test::MockObject;
use Data::Dumper;
use autodie qw(:all);
use Getopt::Long;
use List::MoreUtils qw( any );
use DateTime;
use Readonly;

use Crispr::DB::BaseAdaptor;

# Number of tests in the loop
Readonly my $TESTS_IN_COMMON => 1 + 6 + 5 + 2 + 4 + 4 + 3;
Readonly my %TESTS_FOREACH_DBC => (
    mysql => $TESTS_IN_COMMON,
    sqlite => $TESTS_IN_COMMON,
);
plan tests => $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite};

##  database tests  ##
# Module with a function for creating an empty test database
# and returning a database connection
use lib 't/lib';
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
    push @db_connections, $test_db_connections{$driver};
}

SKIP: {
    skip 'No database connections available', $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite} if !@db_connections;
    
    if( @db_connections == 1 ){
        skip 'Only one database connection available', $TESTS_FOREACH_DBC{sqlite} if $db_connections[0]->driver eq 'mysql';
        skip 'Only one database connection available', $TESTS_FOREACH_DBC{mysql} if $db_connections[0]->driver eq 'sqlite';
    }
}

foreach my $driver ( keys %test_db_connections ){
    my $db_connection = $test_db_connections{$driver};
    my $dbh = $db_connection->connection->dbh;
    # $dbh is a DBI database handle
    local $Test::DatabaseRow::dbh = $dbh;
    
    # make a mock DBConnection object
    my $mock_db_connection = Test::MockObject->new();
    $mock_db_connection->set_isa( 'Crispr::DB::DBConnection' );
    $mock_db_connection->mock( 'dbname', sub { return $db_connection->dbname } );
    $mock_db_connection->mock( 'connection', sub { return $db_connection->connection } );
    
    # make a new BaseAdaptor
    my $base_adaptor = Crispr::DB::BaseAdaptor->new( db_connection => $mock_db_connection );
    # 1 test
    isa_ok( $base_adaptor, 'Crispr::DB::BaseAdaptor', "$driver: test inital Adaptor object class" );
    
    # check method calls 6 tests
    my @methods = qw(
        dbname connection check_entry_exists_in_db fetch_rows_expecting_single_row fetch_rows_for_generic_select_statement
        _db_error_handling
    );
    
    foreach my $method ( @methods ) {
        ok( $base_adaptor->can( $method ), "$driver: $method method test" );
        $tests++;
    }
    
    # insert some data directly into db
    my $statement = "insert into cas9 values( ?, ?, ?, ?, ? );";
    
    my $sth ;
    $sth = $dbh->prepare($statement);
    my ( $name, $type, $vector, $species, ) = ( 'pCS2-ZfnCas9n', 'ZfnCas9n', 'pCS2', 's_pyogenes' );
    $sth->execute( 1, $name, $type, $vector, $species, );
    my ( $name_2, $type_2, $vector_2, $species_2, ) = ( 'pCS2-ZfnCas9-D10An', 'ZfnCas9-D10An', 'pCS2', 's_pyogenes' );
    $sth->execute( 2, $name_2, $type_2, $vector_2, $species_2, );

    #$sth->execute( 1, 'cas9_dnls_native', 'rna', 'cr_test', '2014-10-13', );
    #$sth->execute( 2, 'cas9_dnls_native', 'protein', 'cr_test', '2014-10-13', );
    
    # test check_entry_exists_in_db - 5 tests
    my $check_statement = 'select count(*) from cas9 where cas9_id = ?;';
    my $select_statement = 'select * from cas9 where vector = ?;';
    is( $base_adaptor->check_entry_exists_in_db( $check_statement, [ 1, ] ), 1, "$driver: check entry exists in db 1" );
    is( $base_adaptor->check_entry_exists_in_db( $check_statement, [ 3, ] ), undef, "$driver: check entry exists in db 2" );
    is( $base_adaptor->check_entry_exists_in_db( $select_statement, [ 'pGEM' ] ), undef, "$driver: check entry exists in db 3" );
    throws_ok{ $base_adaptor->check_entry_exists_in_db( $select_statement, [ 'pCS2', ] ) }
        qr/TOO\sMANY\sROWS/xms, "$driver: check entry exists in db throws on too many rows returned";
    throws_ok{ $base_adaptor->check_entry_exists_in_db( 'select count(*) from cas9;', [  ] ) }
        qr/TOO\sMANY\sITEMS/xms, "$driver: check entry exists in db throws on too many items returned";
    
    # fetch_rows_for_generic_select_statement - 2 tests
    $results = $base_adaptor->fetch_rows_for_generic_select_statement( $select_statement, [ 'pCS2', ] );
    is( scalar @{$results}, 2, "$driver: check number of rows returned by fetch_rows_for_generic_select_statement" );
    
    $select_statement = 'select * from cas9 where cas9_id = ?;';
    throws_ok{ $base_adaptor->fetch_rows_for_generic_select_statement( $select_statement, [ 3, ] ) }
        qr/NO\sROWS/xms, "$driver: check fetch_rows_for_generic_select_statement throws on no rows returned";
    
    # fetch_rows_expecting_single_row - 4 tests
    $results = $base_adaptor->fetch_rows_expecting_single_row( $select_statement, [ 1, ] );
    is( join(":", @{$results} ), "1:$name:$type:$vector:$species", "$driver: check fields returned by fetch_rows_expecting_single_row" );
    throws_ok{ $base_adaptor->fetch_rows_expecting_single_row( $select_statement, [ 3, ] ) }
        qr/NO\sROWS/xms, "$driver: check fetch_rows_expecting_single_row throws on no rows returned";
    $select_statement = 'select * from cas9;';
    throws_ok{ $base_adaptor->fetch_rows_expecting_single_row( $select_statement, [  ] ) }
        qr/TOO\sMANY\sROWS/xms, "$driver: check fetch_rows_expecting_single_row throws on too many rows returned";
    $select_statement = 'select * from cas;';
    #throws_ok{ $base_adaptor->fetch_rows_expecting_single_row( $select_statement, [  ] ) }
    #    qr/An unexpected problem occurred/, "$driver: check fetch_rows_expecting_single_row throws on unexpected error";
    
    # check throws ok on unexpected warning as well
    # for this we need to suppress the warning that is generated as well, hence the nested warning_like test
    # This does not affect the apparent number of tests run
    my $warning = $driver eq 'mysql'    ?   'DBD::mysql::st execute failed'
                                        :   'DBD::SQLite::db prepare failed';
    throws_ok{
        warning_like { $base_adaptor->fetch_rows_expecting_single_row( $select_statement, [  ] ) }
            qr/$warning/;
        }
        qr/An unexpected problem occurred/, "$driver: check fetch_rows_expecting_single_row throws on unexpected error";
    
    # check _prepare method - 4 tests
    $select_statement = 'select * from cas9';
    my $where_clause = 'where vector = ?';
    my $sql = join(q{ }, $select_statement, $where_clause, );
    ok( $base_adaptor->_prepare_sql( $select_statement ), "$driver: prepare statement - no where clause" );
    ok( $base_adaptor->_prepare_sql( $sql, $where_clause, [ 'pCS2' ] ), "$driver: prepare statement - where clause and parameters" );
    throws_ok { $base_adaptor->_prepare_sql( $select_statement, $where_clause, undef ) }
        qr/Parameters must be supplied with a where clause/, "$driver: prepare statement - where clause, no parameters";
    throws_ok { $base_adaptor->_prepare_sql( $select_statement, $where_clause, {} ) }
        qr/Parameters to the where clause must be supplied as an ArrayRef/, "$driver: prepare statement - where clause, parameters in HASHREF";
    
    # check _db_error_handling method - 1 test
    my $mock_crRNA_adaptor = Test::MockObject->new();
    $mock_crRNA_adaptor->set_isa('Crispr::DB::crRNAAdaptor');
    throws_ok { $base_adaptor->_db_error_handling( 'NO ROWS at', 'select * from cas9 where cas9_id = ?;', [ 3, ] ) }
        qr/object does not exist in the database/, "$driver: _db_error_handling";
    throws_ok { $base_adaptor->_db_error_handling( 'TOO MANY ROWS at', 'select * from cas9 where cas9_id = ?;', [ 3, ] ) }
        qr/TOO MANY ROWS/, "$driver: _db_error_handling - no entry in HASH";
    throws_ok { $base_adaptor->_db_error_handling( 'too many rows at', 'select * from cas9 where cas9_id = ?;', [ 3, ] ) }
        qr/too many rows/, "$driver: _db_error_handling - error message not in caps";
    
    # drop database
    $test_db_connections{$driver}->destroy();
}

