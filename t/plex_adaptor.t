#!/usr/bin/env perl
# plex_adaptor.t
use warnings;
use strict;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Test::DatabaseRow;
use Data::Dumper;
use DateTime;
use Readonly;

use Crispr::DB::PlexAdaptor;
use Crispr::DB::DBConnection;

# Number of tests
Readonly my $TESTS_IN_COMMON => 1 + 15 + 7 + 2 + 3 + 8 + 6 + 10 + 7 + 1;
Readonly my %TESTS_FOREACH_DBC => (
    mysql => $TESTS_IN_COMMON,
    sqlite => $TESTS_IN_COMMON,
);
plan tests => $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite};

# check attributes and methods - 3 + 12 tests
my @attributes = ( qw{ dbname db_connection connection } );

my @methods = (
    qw{ store store_plex store_plexes fetch_by_id fetch_by_ids
        fetch_by_name _fetch delete_plex_from_db check_entry_exists_in_db fetch_rows_expecting_single_row
        fetch_rows_for_generic_select_statement _db_error_handling }
);

# DB tests
# Module with a function for creating an empty test database
# and returning a database connection
use lib 't/lib';
use TestDB;

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
    
    my $mock_cas9_object = Test::MockObject->new();
    $mock_cas9_object->set_isa( 'Crispr::Cas9' );
    
    my $mock_plex = Test::MockObject->new();
    my $plex_name_1 = 'MPX14';
    $mock_plex->set_isa( 'Crispr::DB::Plex' );
    my $p_id;
    $mock_plex->mock( 'db_id', sub{ my @args = @_; if( $_[1] ){ $p_id = $_[1] } return $p_id; } );
    $mock_plex->mock( 'plex_name', sub{ return lc( $plex_name_1 ) } );
    $mock_plex->mock( 'run_id', sub{ return 13831 } );
    $mock_plex->mock( 'analysis_started', sub{ return '2014-09-27' } );
    $mock_plex->mock( 'analysis_finished', sub{ return '2014-10-03' } );
    
    # make a new real Plex Adaptor
    my $plex_adaptor = Crispr::DB::PlexAdaptor->new( db_connection => $mock_db_connection, );
    # 1 test
    isa_ok( $plex_adaptor, 'Crispr::DB::PlexAdaptor', "$driver: check object class is ok" );
    
    # check attributes and methods exist 3 + 12 tests
    foreach my $attribute ( @attributes ) {
        can_ok( $plex_adaptor, $attribute );
    }
    foreach my $method ( @methods ) {
        can_ok( $plex_adaptor, $method );
    }
    
    # check store - 7 tests
    ok( $plex_adaptor->store( $mock_plex ), "$driver: store" );
    row_ok(
       table => 'plex',
       where => [ plex_id => 1 ],
       tests => {
           'eq' => {
                plex_name => $mock_plex->plex_name,
                analysis_started => $mock_plex->analysis_started,
                analysis_finished => $mock_plex->analysis_finished,
           },
           '==' => {
                run_id => $mock_plex->run_id,
           },
       },
       label => "$driver: plex stored",
    );
    
    # test that store throws properly
    throws_ok { $plex_adaptor->store_plex('Plex') }
        qr/Argument\smust\sbe\sCrispr::DB::Plex\sobject/,
        "$driver: store_plex throws on string input";
    throws_ok { $plex_adaptor->store_plex($mock_cas9_object) }
        qr/Argument\smust\sbe\sCrispr::DB::Plex\sobject/,
        "$driver: store_plex throws if object is not Crispr::DB::Plex";
    
    # check throws ok on attempted duplicate entry
    # for this we need to suppress the warning that is generated as well, hence the nested warning_like test
    # This does not affect the apparent number of tests run
    my $regex = $driver eq 'mysql' ?   qr/Duplicate\sentry/xms
        :                           qr/PRIMARY\sKEY\smust\sbe\sunique/xms;
    
    throws_ok {
        warning_like { $plex_adaptor->store_plex( $mock_plex) }
            $regex;
    }
        $regex, "$driver: store_plex throws because of duplicate entry";
    
    $p_id = 2;
    $plex_name_1 = 'MPX15';
    ok( $plex_adaptor->store_plex( $mock_plex ), "$driver: store_plex" );
    row_ok(
       table => 'plex',
       where => [ plex_id => 2 ],
       tests => {
           'eq' => {
                plex_name => $mock_plex->plex_name,
                analysis_started => $mock_plex->analysis_started,
                analysis_finished => $mock_plex->analysis_finished,
           },
           '==' => {
                run_id => $mock_plex->run_id,
           },
       },
       label => "$driver: plex stored",
    );
    
    # throws ok - 2 tests
    throws_ok { $plex_adaptor->store_plexes('PlexObject') }
        qr/Supplied\sargument\smust\sbe\san\sArrayRef\sof\sPlex\sobjects/,
        "$driver: store_plexes throws on non ARRAYREF";
    throws_ok { $plex_adaptor->store_plexes( [ 'PlexObject' ] ) }
        qr/Argument\smust\sbe\sCrispr::DB::Plex\sobject/,
        "$driver: store_plexes throws on string input";
    
    # increment mock object 1's id
    $p_id = 3;
    $plex_name_1 = 'MPX16';
    # make new mock object for store plexs
    my $mock_plex_2 = Test::MockObject->new();
    my $plex_name_2 = 'MPX17';
    $mock_plex_2->set_isa( 'Crispr::DB::Plex' );
    $mock_plex_2->mock( 'db_id', sub{ return 4; } );
    $mock_plex_2->mock( 'plex_name', sub{ return lc( $plex_name_2 ) } );
    $mock_plex_2->mock( 'run_id', sub{ return 13841 } );
    $mock_plex_2->mock( 'analysis_started', sub{ return '2014-10-03' } );
    $mock_plex_2->mock( 'analysis_finished', sub{ return '2014-10-07' } );
    
    #  store plexes - 3 tests
    ok( $plex_adaptor->store_plexes( [ $mock_plex, $mock_plex_2 ] ), "$driver: store_plexes" );
    row_ok(
       table => 'plex',
       where => [ plex_id => 3 ],
       tests => {
           'eq' => {
                plex_name => $mock_plex->plex_name,
                analysis_started => $mock_plex->analysis_started,
                analysis_finished => $mock_plex->analysis_finished,
           },
           '==' => {
                run_id => $mock_plex->run_id,
           },
       },
       label => "$driver: plex stored",
    );
    row_ok(
       table => 'plex',
       where => [ plex_id => 4 ],
       tests => {
           'eq' => {
                plex_name => $mock_plex_2->plex_name,
                analysis_started => $mock_plex_2->analysis_started,
                analysis_finished => $mock_plex_2->analysis_finished,
           },
           '==' => {
                run_id => $mock_plex_2->run_id,
           },
       },
       label => "$driver: plex stored",
    );
    
    # _fetch - 8 tests
    ok( $plex_adaptor->_fetch(), '_fetch');
    my $plex_from_db = @{ $plex_adaptor->_fetch( 'plex_id = ?', [ 3, ] ) }[0];
    check_attributes( $plex_from_db, $mock_plex, $driver, 'fetch_by_id', );
    throws_ok { $plex_adaptor->_fetch( 'plex_id = ?' ) }
        qr/Parameters\smust\sbe\ssupplied\swith\sa\swhere\sclause/,
        '_fetch throws with where clause but no parameters';
    throws_ok { $plex_adaptor->_fetch( 'plex_id = ?', { id => 3, } ) }
        qr/Parameters\sto\sthe\swhere\sclause\smust\sbe\ssupplied\sas\san\sArrayRef/,
        '_fetch throws with where clause parameters not in ArrayRef';
    
    # fetch_by_id - 6 tests
    $plex_from_db = $plex_adaptor->fetch_by_id( 4 );
    check_attributes( $plex_from_db, $mock_plex_2, $driver, 'fetch_by_id', );
    throws_ok{ $plex_adaptor->fetch_by_id( 10 ) } qr/Couldn't retrieve plex/, 'Plex does not exist in db';
    
    # fetch_by_ids - 10 tests
    my @ids = ( 3, 4 );
    my $plexs_from_db = $plex_adaptor->fetch_by_ids( \@ids );
    
    my @plexes = ( $mock_plex, $mock_plex_2 );
    foreach my $i ( 0..1 ){
        my $plex_from_db = $plexs_from_db->[$i];
        my $mock_plex = $plexes[$i];
        check_attributes( $plex_from_db, $mock_plex, $driver, 'fetch_by_ids', );
    }

    # fetch_by_name - 7 tests
    ok( $plex_from_db = $plex_adaptor->fetch_by_name( 'MPX17' ), 'fetch_by_name');
    check_attributes( $plex_from_db, $mock_plex_2, $driver, 'fetch_by_name', );
    throws_ok{ $plex_adaptor->fetch_by_name( 'MPX18' ) } qr/Couldn't retrieve plex/, 'fetch_by_name: Plex does not exist in db';

TODO: {
    local $TODO = 'methods not implemented yet.';
    
    ok( $plex_adaptor->delete_plex_from_db ( 'rna' ), 'delete_plex_from_db');

}
    $db_connection->destroy();
}

sub check_attributes {
    my ( $object1, $object2, $driver, $method ) = @_;
    is( $object1->db_id, $object2->db_id, "$driver: object from db $method - check db_id");
    is( $object1->plex_name, $object2->plex_name, "$driver: object from db $method - check plex_name");
    is( $object1->run_id, $object2->run_id, "$driver: object from db $method - check run_id");
    is( $object1->analysis_started, $object2->analysis_started, "$driver: object from db $method - check analysis_started");
    is( $object1->analysis_finished, $object2->analysis_finished, "$driver: object from db $method - check analysis_finished");
}

