#!/usr/bin/env perl
# cas9_prep_adaptor.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Test::DatabaseRow;
use Data::Dumper;
use DateTime;
use Readonly;

use Crispr::DB::Cas9PrepAdaptor;

Readonly my $TESTS_IN_COMMON => 1 + 21 + 12 + 1 + 12 + 5 + 8 + 10 + 1;
Readonly my %TESTS_FOREACH_DBC => (
    mysql => $TESTS_IN_COMMON,
    sqlite => $TESTS_IN_COMMON,
);
plan tests => $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite};

# check attributes and methods - 3 + 18 tests
my @attributes = ( qw{ dbname db_connection connection } );

my @methods = (
    qw{ store store_cas9_prep store_cas9_preps fetch_by_id fetch_by_ids
        fetch_without_db_id fetch_all_by_type_and_date fetch_all_by_type fetch_all_by_date fetch_all_by_made_by
        fetch_all_by_prep_type _make_new_object_from_db _make_new_cas9_prep_from_db delete_cas9_prep_from_db check_entry_exists_in_db
        fetch_rows_expecting_single_row fetch_rows_for_generic_select_statement _db_error_handling }
);

# DB tests
# Module with a function for creating an empty test database
# and returning a database connection
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
    
    # make mock Cas9 and Cas9Prep objects
    my $type = 'cas9_dnls_native';
    my $species = 's_pyogenes';
    my $target_seq = 'NNNNNNNNNNNNNNNNNN';
    my $pam = 'NGG';
    my $crispr_target_seq = $target_seq . $pam;
    my $mock_cas9_object = Test::MockObject->new();
    $mock_cas9_object->set_isa( 'Crispr::Cas9' );
    $mock_cas9_object->mock( 'type', sub{ return $type } );
    $mock_cas9_object->mock( 'species', sub{ return $species } );
    $mock_cas9_object->mock( 'target_seq', sub{ return $target_seq } );
    $mock_cas9_object->mock( 'PAM', sub{ return $pam } );
    $mock_cas9_object->mock( 'crispr_target_seq', sub{ return $crispr_target_seq } );
    $mock_cas9_object->mock( 'info', sub{ return ( $type, $species, $crispr_target_seq ) } );

    my $type_2 = 'cas9_dnls_nickase';
    my $mock_cas9_object_2 = Test::MockObject->new();
    $mock_cas9_object_2->set_isa( 'Crispr::Cas9' );
    $mock_cas9_object_2->mock( 'type', sub{ return $type_2 } );
    $mock_cas9_object_2->mock( 'species', sub{ return $species } );
    $mock_cas9_object_2->mock( 'target_seq', sub{ return $target_seq } );
    $mock_cas9_object_2->mock( 'PAM', sub{ return $pam } );
    $mock_cas9_object_2->mock( 'crispr_target_seq', sub{ return $crispr_target_seq } );
    $mock_cas9_object_2->mock( 'info', sub{ return ( $type_2, $species, $crispr_target_seq ) } );
    
    my $prep_type = 'rna';
    my $made_by = 'cr_test';
    my $todays_date_obj = DateTime->now();
    my $mock_cas9_prep_object_1 = Test::MockObject->new();
    $mock_cas9_prep_object_1->set_isa( 'Crispr::DB::Cas9Prep' );
    $mock_cas9_prep_object_1->mock( 'db_id', sub{ return undef } );
    $mock_cas9_prep_object_1->mock( 'cas9', sub{ return $mock_cas9_object } );
    $mock_cas9_prep_object_1->mock( 'prep_type', sub{ return $prep_type } );
    $mock_cas9_prep_object_1->mock( 'made_by', sub{ return $made_by } );
    $mock_cas9_prep_object_1->mock( 'date', sub{ return $todays_date_obj->ymd } );
    $mock_cas9_prep_object_1->mock( 'type', sub{ return $mock_cas9_object->type } );
    
    my $mock_cas9_prep_object_2 = Test::MockObject->new();
    my $prep_type_2 = 'protein';
    $mock_cas9_prep_object_2->set_isa( 'Crispr::DB::Cas9Prep' );
    $mock_cas9_prep_object_2->mock( 'db_id', sub{ return undef } );
    $mock_cas9_prep_object_2->mock( 'cas9', sub{ return $mock_cas9_object } );
    $mock_cas9_prep_object_2->mock( 'prep_type', sub{ return $prep_type_2 } );
    $mock_cas9_prep_object_2->mock( 'made_by', sub{ return 'cr_test' } );
    $mock_cas9_prep_object_2->mock( 'date', sub{ return $todays_date_obj->ymd } );
    $mock_cas9_prep_object_2->mock( 'type', sub{ return $mock_cas9_object->type } );

    my $mock_cas9_prep_object_3 = Test::MockObject->new();
    my $prep_type_3 = 'rna';
    $mock_cas9_prep_object_3->set_isa( 'Crispr::DB::Cas9Prep' );
    $mock_cas9_prep_object_3->mock( 'db_id', sub{ return undef } );
    $mock_cas9_prep_object_3->mock( 'cas9', sub{ return $mock_cas9_object_2 } );
    $mock_cas9_prep_object_3->mock( 'prep_type', sub{ return $prep_type_3 } );
    $mock_cas9_prep_object_3->mock( 'made_by', sub{ return 'cr_test2' } );
    $mock_cas9_prep_object_3->mock( 'date', sub{ return $todays_date_obj->ymd } );
    $mock_cas9_prep_object_3->mock( 'type', sub{ return $mock_cas9_object_2->type } );

    my $mock_cas9_prep_object_4 = Test::MockObject->new();
    my $prep_type_4 = 'protein';
    $mock_cas9_prep_object_4->set_isa( 'Crispr::DB::Cas9Prep' );
    $mock_cas9_prep_object_4->mock( 'db_id', sub{ return undef } );
    $mock_cas9_prep_object_4->mock( 'cas9', sub{ return $mock_cas9_object_2 } );
    $mock_cas9_prep_object_4->mock( 'prep_type', sub{ return $prep_type_4 } );
    $mock_cas9_prep_object_4->mock( 'made_by', sub{ return 'cr_test2' } );
    $mock_cas9_prep_object_4->mock( 'date', sub{ return $todays_date_obj->ymd } );
    $mock_cas9_prep_object_4->mock( 'type', sub{ return $mock_cas9_object_2->type } );

    # make a new real Cas9Prep Adaptor
    my $cas9_prep_adaptor = Crispr::DB::Cas9PrepAdaptor->new( db_connection => $mock_db_connection, );
    # 1 test
    isa_ok( $cas9_prep_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: check object class is ok" );
    
    # check attributes and methods exist 3 + 17 tests
    foreach my $attribute ( @attributes ) {
        can_ok( $cas9_prep_adaptor, $attribute );
    }
    foreach my $method ( @methods ) {
        can_ok( $cas9_prep_adaptor, $method );
    }
    
    # check store methods 12 tests
    throws_ok { $cas9_prep_adaptor->store('Cas9PrepObject') } qr/Argument\smust\sbe\sCrispr::DB::Cas9Prep\sobject/, "$driver: store throws on string input";
    ok( $cas9_prep_adaptor->store( $mock_cas9_prep_object_1 ), "$driver: store" );
    row_ok(
       table => 'cas9',
       where => [ cas9_id => 1 ],
       tests => {
           'eq' => {
                cas9_type => $mock_cas9_prep_object_1->type,
                prep_type => $mock_cas9_prep_object_1->prep_type,
                made_by  => $mock_cas9_prep_object_1->made_by,
                date => $mock_cas9_prep_object_1->date,
           },
       },
       label => "$driver: cas9_prep stored",
    );
        

    throws_ok { $cas9_prep_adaptor->store_cas9_prep('Cas9PrepObject') }
        qr/Argument\smust\sbe\sCrispr::DB::Cas9Prep\sobject/, "$driver: store_cas9_prep throws on string input";
    $regex = $driver eq 'mysql' ?   qr/Duplicate\sentry/xms
        :                           qr/not\sunique/xms;
    
    throws_ok { $cas9_prep_adaptor->store_cas9_prep( $mock_cas9_prep_object_1) }
        $regex, "$driver: store_cas9_prep throws because of duplicate entry";
    ok( $cas9_prep_adaptor->store_cas9_prep( $mock_cas9_prep_object_2 ), "$driver: store_cas9_prep" );
    my $cas9_id = $driver eq 'mysql'    ?   3
        :                                   2;
    row_ok(
       table => 'cas9',
       where => [ cas9_id => $cas9_id ],
       tests => {
           'eq' => {
                cas9_type => $mock_cas9_prep_object_2->type,
                prep_type => $mock_cas9_prep_object_2->prep_type,
                made_by  => $mock_cas9_prep_object_2->made_by,
                date => $mock_cas9_prep_object_2->date,
           },
       },
       label => "$driver: cas9_prep 2 stored",
    );

    throws_ok { $cas9_prep_adaptor->store_cas9_preps('Cas9PrepObject') } qr/Supplied\sargument\smust\sbe\san\sArrayRef\sof\sCas9Prep\sobjects/, "$driver: store_cas9_preps throws on non ARRAYREF";
    throws_ok { $cas9_prep_adaptor->store_cas9_preps( [ 'Cas9PrepObject' ] ) } qr/Argument\smust\sbe\sCrispr::DB::Cas9Prep\sobject/, "$driver: store_cas9_preps throws on string input";
    
    ok( $cas9_prep_adaptor->store_cas9_preps( [ $mock_cas9_prep_object_3, $mock_cas9_prep_object_4 ] ), "$driver: store_cas9_preps" );
    $cas9_id = $driver eq 'mysql'    ?  4
        :                               3;
    row_ok(
       table => 'cas9',
       where => [ cas9_id => $cas9_id ],
       tests => {
           'eq' => {
                cas9_type => $mock_cas9_prep_object_3->type,
                prep_type => $mock_cas9_prep_object_3->prep_type,
                made_by  => $mock_cas9_prep_object_3->made_by,
                date => $mock_cas9_prep_object_3->date,
           },
       },
       label => "$driver: cas9_prep 3 stored",
    );
    $cas9_id = $driver eq 'mysql'    ?  5
        :                               4;
    row_ok(
       table => 'cas9',
       where => [ cas9_id => $cas9_id ],
       tests => {
           'eq' => {
                cas9_type => $mock_cas9_prep_object_4->type,
                prep_type => $mock_cas9_prep_object_4->prep_type,
                made_by  => $mock_cas9_prep_object_4->made_by,
                date => $mock_cas9_prep_object_4->date,
           },
       },
       label => "$driver: cas9_prep 4 stored",
    );

    throws_ok{ $cas9_prep_adaptor->fetch_by_id( 10 ) } qr/Couldn't retrieve cas9_prep/, 'Cas9prep does not exist in db';
    
    # fetch methods - 12 tests
    my $cas9_from_db_1;
    ok( $cas9_from_db_1 = $cas9_prep_adaptor->_make_new_cas9_prep_from_db( [ '1', 'cas9_dnls_native', 'rna', 'cr_test', '2014-10-02' ] ), '_make_new_cas9_prep_from_db');
    is( $cas9_from_db_1->db_id, 1, "$driver: object from db - check db_id");
    is( $cas9_from_db_1->type, 'cas9_dnls_native', "$driver: object from db - check type");
    is( $cas9_from_db_1->prep_type, 'rna', "$driver: object from db - check prep_type");
    is( $cas9_from_db_1->made_by, 'cr_test', "$driver: object from db - check made_by");
    is( $cas9_from_db_1->date, '2014-10-02', "$driver: object from db - check date");
    
    ok( $cas9_from_db_1 = $cas9_prep_adaptor->_make_new_object_from_db( [ '2', 'cas9_dnls_nickase', 'dna', 'cr_test2', '2014-10-03' ] ), '_make_new_object_from_db');
    is( $cas9_from_db_1->db_id, 2, "$driver: object from db - check db_id");
    is( $cas9_from_db_1->type, 'cas9_dnls_nickase', "$driver: object from db - check type");
    is( $cas9_from_db_1->prep_type, 'dna', "$driver: object from db - check prep_type");
    is( $cas9_from_db_1->made_by, 'cr_test2', "$driver: object from db - check made_by");
    is( $cas9_from_db_1->date, '2014-10-03', "$driver: object from db - check date");

    SKIP: {
        my $cas9_from_db = $cas9_prep_adaptor->fetch_by_id( 1 );
        
        skip "No cas9 returned from db!", 5 if !$cas9_from_db;
        # test attributes
        is( $cas9_from_db->db_id, 1, "$driver: object from db - check db id");
        is( $cas9_from_db->type, $mock_cas9_prep_object_1->type, "$driver: object from db - check type");
        is( $cas9_from_db->prep_type, $mock_cas9_prep_object_1->prep_type, "$driver: object from db - check prep_type");
        is( $cas9_from_db->made_by, $mock_cas9_prep_object_1->made_by, "$driver: object from db - check made_by");
        is( $cas9_from_db->date, $mock_cas9_prep_object_1->date, "$driver: object from db - check date");
    }
    
    SKIP:{
        my @ids = $driver eq 'mysql' ?      ( 3, 4 )
            :                               ( 2, 3 );
        my $cas9_objects_from_db = $cas9_prep_adaptor->fetch_by_ids( \@ids );
        
        skip "No cas9 objects returned from db!", 8 if !defined $cas9_objects_from_db->[0] || !defined $cas9_objects_from_db->[1];
        my @cas9_preps = ( $mock_cas9_prep_object_2, $mock_cas9_prep_object_3 );
        foreach my $i ( 0..1 ){
            my $cas9_from_db = $cas9_objects_from_db->[$i];
            $prep = $cas9_preps[$i];
            is( $cas9_from_db->type, $prep->type, "$driver: object from db - check type");
            is( $cas9_from_db->prep_type, $prep->prep_type, "$driver: object from db - check prep_type");
            is( $cas9_from_db->made_by, $prep->made_by, "$driver: object from db - check made_by");
            is( $cas9_from_db->date, $prep->date, "$driver: object from db - check date");
        }
    }
    
    # check other fetch methods - 10 test
    my $cas9_preps;
    ok( $cas9_preps = $cas9_prep_adaptor->fetch_all_by_type_and_date( 'cas9_dnls_nickase', $todays_date_obj->ymd ), 'fetch_all_by_type_and_date');
    is( scalar @{$cas9_preps}, 2, "check number returned by type and date");
    ok( $cas9_preps = $cas9_prep_adaptor->fetch_all_by_type( 'cas9_dnls_native' ), 'fetch_all_by_type');
    is( scalar @{$cas9_preps}, 2, "check number returned by fetch_all_by_type");
    ok( $cas9_preps = $cas9_prep_adaptor->fetch_all_by_date( $todays_date_obj->ymd ), 'fetch_all_by_date');
    is( scalar @{$cas9_preps}, 4, "check number returned by date");
    ok( $cas9_preps = $cas9_prep_adaptor->fetch_all_by_made_by( 'cr_test' ), 'fetch_all_by_made_by');
    is( scalar @{$cas9_preps}, 2, "check number returned by fetch_all_by_made_by");
    ok( $cas9_preps = $cas9_prep_adaptor->fetch_all_by_prep_type( 'rna' ), 'fetch_all_by_prep_type');
    is( scalar @{$cas9_preps}, 2, "check number returned by fetch_all_by_prep_type");
    
    #TODO 1 tests
TODO: {
    local $TODO = 'methods not implemented yet.';
    
    ok( $cas9_prep_adaptor->delete_cas9_prep_from_db ( 'rna' ), 'delete_cas9_prep_from_db');
}
    
}

# drop databases
foreach ( @db_adaptors ){
    $_->destroy();
}
