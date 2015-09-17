#!/usr/bin/env perl
# cas9_adaptor.t
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

use Crispr::DB::Cas9Adaptor;

Readonly my $TESTS_IN_COMMON => 1 + 18 + 12 + 1 + 6 + 6 + 12 + 12 + 6 + 1 + 4 + 1;
Readonly my %TESTS_FOREACH_DBC => (
    mysql => $TESTS_IN_COMMON,
    sqlite => $TESTS_IN_COMMON,
);
plan tests => $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite};

# check attributes and methods - 3 + 15 tests
my @attributes = ( qw{ dbname db_connection connection } );

my @methods = (
    qw{ store store_cas9 store_cas9s fetch_by_id fetch_by_ids
        fetch_all_by_type fetch_by_name get_db_id_by_name _fetch _make_new_cas9_from_db
        delete_cas9_from_db check_entry_exists_in_db fetch_rows_expecting_single_row fetch_rows_for_generic_select_statement _db_error_handling }
);

# DB tests
# Module with a function for creating an empty test database
# and returning a database connection
use lib 't/lib';
use TestDB;

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

if( !$ENV{MYSQL_DBNAME} || !$ENV{MYSQL_DBUSER} || !$ENV{MYSQL_DBPASS} ){
    die "The following environment variables need to be set for connecting to the database!\n",
        "MYSQL_DBNAME, MYSQL_DBUSER, MYSQL_DBPASS"; 
}

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
    
    # make mock Cas9 object
    my $type = 'ZfnCas9n';
    my $species = 's_pyogenes';
    my $target_seq = 'NNNNNNNNNNNNNNNNNN';
    my $pam = 'NGG';
    my $crispr_target_seq = $target_seq . $pam;
    my $vector = 'pCS2';
    my $name = join(q{-}, $vector, $type, );

    my $mock_cas9_object_1 = Test::MockObject->new();
    $mock_cas9_object_1->set_isa( 'Crispr::Cas9' );
    $mock_cas9_object_1->mock( 'db_id', sub{ return 1 } );
    $mock_cas9_object_1->mock( 'type', sub{ return $type } );
    $mock_cas9_object_1->mock( 'species', sub{ return $species } );
    $mock_cas9_object_1->mock( 'target_seq', sub{ return $target_seq } );
    $mock_cas9_object_1->mock( 'PAM', sub{ return $pam } );
    $mock_cas9_object_1->mock( 'crispr_target_seq', sub{ return $crispr_target_seq } );
    $mock_cas9_object_1->mock( 'info', sub{ return ( $type, $species, $crispr_target_seq ) } );
    $mock_cas9_object_1->mock( 'name', sub{ return $name } );
    $mock_cas9_object_1->mock( 'vector', sub{ return $vector } );

    my $type_2 = 'ZfnCas9-D10An';
    my $mock_cas9_object_2 = Test::MockObject->new();
    my $name_2 = join(q{-}, $vector, $type_2, );
    $mock_cas9_object_2->set_isa( 'Crispr::Cas9' );
    $mock_cas9_object_2->mock( 'db_id', sub{ return 2 } );
    $mock_cas9_object_2->mock( 'type', sub{ return $type_2 } );
    $mock_cas9_object_2->mock( 'species', sub{ return $species } );
    $mock_cas9_object_2->mock( 'target_seq', sub{ return $target_seq } );
    $mock_cas9_object_2->mock( 'PAM', sub{ return $pam } );
    $mock_cas9_object_2->mock( 'crispr_target_seq', sub{ return $crispr_target_seq } );
    $mock_cas9_object_2->mock( 'info', sub{ return ( $type_2, $species, $crispr_target_seq ) } );
    $mock_cas9_object_2->mock( 'name', sub{ return $name_2 } );
    $mock_cas9_object_2->mock( 'vector', sub{ return $vector } );

    my $type_3 = 'ZfnCas9n';
    my $vector_3_4 = 'pGEM';
    my $mock_cas9_object_3 = Test::MockObject->new();
    my $name_3 = join(q{-}, $vector_3_4, $type_3, );
    $mock_cas9_object_3->set_isa( 'Crispr::Cas9' );
    $mock_cas9_object_3->mock( 'db_id', sub{ return 3 } );
    $mock_cas9_object_3->mock( 'type', sub{ return $type_3 } );
    $mock_cas9_object_3->mock( 'species', sub{ return $species } );
    $mock_cas9_object_3->mock( 'target_seq', sub{ return $target_seq } );
    $mock_cas9_object_3->mock( 'PAM', sub{ return $pam } );
    $mock_cas9_object_3->mock( 'crispr_target_seq', sub{ return $crispr_target_seq } );
    $mock_cas9_object_3->mock( 'info', sub{ return ( $type_3, $species, $crispr_target_seq ) } );
    $mock_cas9_object_3->mock( 'name', sub{ return $name_3 } );
    $mock_cas9_object_3->mock( 'vector', sub{ return $vector_3_4 } );

    my $type_4 = 'ZfnCas9-D10An';
    my $mock_cas9_object_4 = Test::MockObject->new();
    my $name_4 = join(q{-}, $vector_3_4, $type_4, );
    $mock_cas9_object_4->set_isa( 'Crispr::Cas9' );
    $mock_cas9_object_4->mock( 'db_id', sub{ return 4 } );
    $mock_cas9_object_4->mock( 'type', sub{ return $type_4 } );
    $mock_cas9_object_4->mock( 'species', sub{ return $species } );
    $mock_cas9_object_4->mock( 'target_seq', sub{ return $target_seq } );
    $mock_cas9_object_4->mock( 'PAM', sub{ return $pam } );
    $mock_cas9_object_4->mock( 'crispr_target_seq', sub{ return $crispr_target_seq } );
    $mock_cas9_object_4->mock( 'info', sub{ return ( $type_4, $species, $crispr_target_seq ) } );
    $mock_cas9_object_4->mock( 'name', sub{ return $name_4 } );
    $mock_cas9_object_4->mock( 'vector', sub{ return $vector_3_4 } );

    # make a new real Cas9 Adaptor
    my $cas9_adaptor = Crispr::DB::Cas9Adaptor->new( db_connection => $mock_db_connection, );
    # 1 test
    isa_ok( $cas9_adaptor, 'Crispr::DB::Cas9Adaptor', "$driver: check object class is ok" );
    
    # check attributes and methods exist 3 + 13 tests
    foreach my $attribute ( @attributes ) {
        can_ok( $cas9_adaptor, $attribute );
    }
    foreach my $method ( @methods ) {
        can_ok( $cas9_adaptor, $method );
    }
    
    # check store methods 12 tests
    throws_ok { $cas9_adaptor->store('Cas9Object') } qr/Argument\smust\sbe\sCrispr::Cas9\sobject/, "$driver: store throws on string input";
    ok( $cas9_adaptor->store( $mock_cas9_object_1 ), "$driver: store" );
    row_ok(
       table => 'cas9',
       where => [ cas9_id => 1 ],
       tests => {
           'eq' => {
                type => $mock_cas9_object_1->type,
                name => $mock_cas9_object_1->name,
           },
       },
       label => "$driver: cas9 stored",
    );
        

    throws_ok { $cas9_adaptor->store_cas9('Cas9Object') }
        qr/Argument\smust\sbe\sCrispr::Cas9\sobject/, "$driver: store_cas9 throws on string input";
    
    # check throws ok on attempted duplicate entry
    # for this we need to suppress the warning that is generated as well, hence the nested warning_like test
    # This does not affect the apparent number of tests run
    my $regex = $driver eq 'mysql' ?   qr/Duplicate\sentry/xms
        :                           qr/PRIMARY\sKEY\smust\sbe\sunique/xms;
    
    throws_ok {
        warning_like { $cas9_adaptor->store_cas9( $mock_cas9_object_1) }
        $regex;
    }
    $regex, "$driver: store_cas9 throws because of duplicate entry";


    ok( $cas9_adaptor->store_cas9( $mock_cas9_object_2 ), "$driver: store_cas9" );
    my $cas9_id = $driver eq 'mysql'    ?   3
        :                                   2;
    row_ok(
       table => 'cas9',
       where => [ cas9_id => 2 ],
       tests => {
           'eq' => {
                type => $mock_cas9_object_2->type,
                name => $mock_cas9_object_2->name,
           },
       },
       label => "$driver: cas9 2 stored",
    );

    throws_ok { $cas9_adaptor->store_cas9s('Cas9Object') } qr/Supplied\sargument\smust\sbe\san\sArrayRef\sof\sCas9\sobjects/, "$driver: store_cas9s throws on non ARRAYREF";
    throws_ok { $cas9_adaptor->store_cas9s( [ 'Cas9Object' ] ) } qr/Argument\smust\sbe\sCrispr::Cas9\sobject/, "$driver: store_cas9s throws on string input";
    
    ok( $cas9_adaptor->store_cas9s( [ $mock_cas9_object_3, $mock_cas9_object_4 ] ), "$driver: store_cas9s" );
    #$cas9_id = $driver eq 'mysql'    ?  4
    #    :                               3;
    row_ok(
       table => 'cas9',
       where => [ cas9_id => 3 ],
       tests => {
           'eq' => {
                type => $mock_cas9_object_3->type,
                name => $mock_cas9_object_3->name,
           },
       },
       label => "$driver: cas9 3 stored",
    );
    #$cas9_id = $driver eq 'mysql'    ?  5
    #    :                               4;
    row_ok(
       table => 'cas9',
       where => [ cas9_id => 4 ],
       tests => {
           'eq' => {
                type => $mock_cas9_object_4->type,
                name => $mock_cas9_object_4->name,
           },
       },
       label => "$driver: cas9 4 stored",
    );

    throws_ok{ $cas9_adaptor->fetch_by_id( 10 ) } qr/Couldn't retrieve cas9/, 'Cas9prep does not exist in db';
    
    # fetch methods
    # _fetch - 6 tests
    my $cas9_from_db_1 = $cas9_adaptor->_fetch('cas9_id = ?;', [ 1, ] );
    check_attributes( $cas9_from_db_1->[0], $mock_cas9_object_1, $driver, '_fetch' );
    
    # fetch by id - 6 tests
    SKIP: {
        my $cas9_from_db = $cas9_adaptor->fetch_by_id( 1 );
        
        skip "No cas9 returned from db!", 7 if !$cas9_from_db;
        # test attributes
        check_attributes( $cas9_from_db, $mock_cas9_object_1, $driver, 'fetch_by_id' );
    }
    
    # fetch by ids - 12 tests
    SKIP:{
        my $cas9_objects_from_db = $cas9_adaptor->fetch_by_ids( [ 3, 4 ] );
        
        skip "No cas9 objects returned from db!", 14 if !defined $cas9_objects_from_db->[0];
        my @cas9s = ( $mock_cas9_object_3, $mock_cas9_object_4 );
        foreach my $i ( 0..1 ){
            my $cas9_from_db = $cas9_objects_from_db->[$i];
            my $mock_cas9 = $cas9s[$i];
            check_attributes( $cas9_from_db, $mock_cas9, $driver, 'fetch_by_ids' );
        }
    }
    
    # fetch all by type - 2 X 6 tests
    SKIP:{
        my $cas9_objects_from_db = $cas9_adaptor->fetch_all_by_type( 'ZfnCas9n' );
        
        skip "No cas9 objects returned from db!", 7 if !defined $cas9_objects_from_db;
        # test attributes
        my @mock_objects = ( $mock_cas9_object_1, $mock_cas9_object_3 );
        my $i = 0;
        foreach my $cas9_object_from_db ( @{$cas9_objects_from_db} ){
            my $mock_obj = $mock_objects[$i];
            check_attributes( $cas9_object_from_db, $mock_obj, $driver, 'fetch_all_by_type' );
            $i++;
        }
    }
    
    # fetch by plasmid name - 6 tests
    SKIP:{
        my $cas9_object_from_db = $cas9_adaptor->fetch_by_name( 'pCS2-ZfnCas9n' );
        
        skip "No cas9 objects returned from db!", 7 if !defined $cas9_object_from_db;
        # test attributes
        check_attributes( $cas9_object_from_db, $mock_cas9_object_1, $driver, 'fetch_by_name' );
    }
    
    # get_db_id_by_name - 1 test
    is( $cas9_adaptor->get_db_id_by_name( 'pCS2-ZfnCas9n' ), 1, "$driver: get_db_id_by_name" );

    # check _make_new_cas9_from_db - 4 tests
    throws_ok { $cas9_adaptor->_make_new_cas9_from_db() } qr/NO INPUT!/, '_make_new_cas9_from_db - throws on no input';
    throws_ok { $cas9_adaptor->_make_new_cas9_from_db( 'STRING' ) } qr/INPUT NOT ARRAYREF!/, '_make_new_cas9_from_db - throws on non ArrayRef';
    throws_ok { $cas9_adaptor->_make_new_cas9_from_db( [  ] ) } qr/WRONG NUMBER OF COLUMNS!/, '_make_new_cas9_from_db - throws on non ArrayRef';
    ok( $cas9_adaptor->_make_new_cas9_from_db(
        [ $mock_cas9_object_1->db_id,
            $mock_cas9_object_1->name,
            $mock_cas9_object_1->type,
            $mock_cas9_object_1->vector,
            $mock_cas9_object_1->species,
        ] ), '_make_new_cas9_from_db' );
    
    #TODO 1 tests
TODO: {
    local $TODO = 'methods not implemented yet.';
    
    
    ok( $cas9_adaptor->delete_cas9_from_db ( 'pCS2-ZfnCas9n' ), 'delete_cas9_from_db');
}
    $db_connection->destroy;
    
}

sub check_attributes {
    my ( $object1, $object2, $driver, $method ) = @_;
    is( $object1->db_id, $object2->db_id, "$driver: object from db $method - check db_id");
    is( $object1->type, $object2->type, "$driver: object from db $method - check type");
    is( $object1->species, $object2->species, "$driver: object from db $method - check species");
    is( $object1->target_seq, $object2->target_seq, "$driver: object from db $method - check target_seq");
    is( $object1->PAM, $object2->PAM, "$driver: object from db $method - check PAM");
    is( $object1->name, $object2->name, "$driver: object from db $method - check name");
}
