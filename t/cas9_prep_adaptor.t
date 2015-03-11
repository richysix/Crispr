#!/usr/bin/env perl
# cas9_prep_adaptor.t
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
use Crispr::DB::Cas9PrepAdaptor;

Readonly my $TESTS_IN_COMMON => 1 + 21 + 12 + 9 + 9 + 9 + 16 + 10 + 1;
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
    # make a new real Cas9 Adaptor
    my $cas9_adaptor = Crispr::DB::Cas9Adaptor->new( db_connection => $mock_db_connection, );
    
    # make mock Cas9 and Cas9Prep objects
    my $type = 'ZfnCas9n';
    my $vector ='pCS2';
    my $name = join(q{-}, $vector, $type, );
    my $species = 's_pyogenes';
    my $target_seq = 'NNNNNNNNNNNNNNNNNN';
    my $pam = 'NGG';
    my $crispr_target_seq = $target_seq . $pam;
    my $mock_cas9_object = Test::MockObject->new();
    $mock_cas9_object->set_isa( 'Crispr::Cas9' );
    $mock_cas9_object->mock( 'db_id', sub{ return 1 } );
    $mock_cas9_object->mock( 'type', sub{ return $type } );
    $mock_cas9_object->mock( 'species', sub{ return $species } );
    $mock_cas9_object->mock( 'target_seq', sub{ return $target_seq } );
    $mock_cas9_object->mock( 'PAM', sub{ return $pam } );
    $mock_cas9_object->mock( 'name', sub{ return $name } );
    $mock_cas9_object->mock( 'vector', sub{ return $vector } );
    $mock_cas9_object->mock( 'crispr_target_seq', sub{ return $crispr_target_seq } );
    $mock_cas9_object->mock( 'info', sub{ return ( $type, $species, $crispr_target_seq ) } );
    # add cas9 directly to db
    my $insert_st = 'insert into cas9 values( ?, ?, ?, ?, ? );';
    my $sth = $dbh->prepare( $insert_st );
    $sth->execute(  undef,
        $mock_cas9_object->name,
        $mock_cas9_object->type,
        $mock_cas9_object->vector,
        $mock_cas9_object->species,
    );
    
    my $type_2 = 'ZfnCas9-D10An';
    my $name_2 = join(q{-}, $vector, $type_2, );
    my $mock_cas9_object_2 = Test::MockObject->new();
    $mock_cas9_object_2->set_isa( 'Crispr::Cas9' );
    $mock_cas9_object_2->mock( 'db_id', sub{ return 2 } );
    $mock_cas9_object_2->mock( 'type', sub{ return $type_2 } );
    $mock_cas9_object_2->mock( 'species', sub{ return $species } );
    $mock_cas9_object_2->mock( 'target_seq', sub{ return $target_seq } );
    $mock_cas9_object_2->mock( 'name', sub{ return $name_2 } );
    $mock_cas9_object_2->mock( 'vector', sub{ return $vector } );
    $mock_cas9_object_2->mock( 'PAM', sub{ return $pam } );
    $mock_cas9_object_2->mock( 'crispr_target_seq', sub{ return $crispr_target_seq } );
    $mock_cas9_object_2->mock( 'info', sub{ return ( $type_2, $species, $crispr_target_seq ) } );
    
    my $prep_type = 'rna';
    my $made_by = 'cr_test';
    my $todays_date_obj = DateTime->now();
    my $mock_cas9_prep_object_1 = Test::MockObject->new();
    $mock_cas9_prep_object_1->set_isa( 'Crispr::DB::Cas9Prep' );
    $mock_cas9_prep_object_1->mock( 'db_id', sub{ return 1 } );
    $mock_cas9_prep_object_1->mock( 'cas9', sub{ return $mock_cas9_object } );
    $mock_cas9_prep_object_1->mock( 'prep_type', sub{ return $prep_type } );
    $mock_cas9_prep_object_1->mock( 'made_by', sub{ return $made_by } );
    $mock_cas9_prep_object_1->mock( 'date', sub{ return $todays_date_obj->ymd } );
    $mock_cas9_prep_object_1->mock( 'type', sub{ return $mock_cas9_object->type } );
    $mock_cas9_prep_object_1->mock( 'notes', sub{ return 'some notes' } );
    #$mock_cas9_prep_object_1->mock( 'cas9_adaptor', sub{ return $cas9_adaptor } );
    
    
    my $mock_cas9_prep_object_2 = Test::MockObject->new();
    my $prep_type_2 = 'protein';
    $mock_cas9_prep_object_2->set_isa( 'Crispr::DB::Cas9Prep' );
    $mock_cas9_prep_object_2->mock( 'db_id', sub{ return 2 } );
    $mock_cas9_prep_object_2->mock( 'cas9', sub{ return $mock_cas9_object } );
    $mock_cas9_prep_object_2->mock( 'prep_type', sub{ return $prep_type_2 } );
    $mock_cas9_prep_object_2->mock( 'made_by', sub{ return 'cr_test' } );
    $mock_cas9_prep_object_2->mock( 'date', sub{ return $todays_date_obj->ymd } );
    $mock_cas9_prep_object_2->mock( 'type', sub{ return $mock_cas9_object->type } );
    $mock_cas9_prep_object_2->mock( 'notes', sub{ return 'some notes' } );
    #$mock_cas9_prep_object_2->mock( 'cas9_adaptor', sub{ return $cas9_adaptor } );

    my $mock_cas9_prep_object_3 = Test::MockObject->new();
    my $prep_type_3 = 'rna';
    $mock_cas9_prep_object_3->set_isa( 'Crispr::DB::Cas9Prep' );
    $mock_cas9_prep_object_3->mock( 'db_id', sub{ return 3 } );
    $mock_cas9_prep_object_3->mock( 'cas9', sub{ return $mock_cas9_object_2 } );
    $mock_cas9_prep_object_3->mock( 'prep_type', sub{ return $prep_type_3 } );
    $mock_cas9_prep_object_3->mock( 'made_by', sub{ return 'cr_test2' } );
    $mock_cas9_prep_object_3->mock( 'date', sub{ return $todays_date_obj->ymd } );
    $mock_cas9_prep_object_3->mock( 'type', sub{ return $mock_cas9_object_2->type } );
    $mock_cas9_prep_object_3->mock( 'notes', sub{ return 'some different notes' } );
    #$mock_cas9_prep_object_3->mock( 'cas9_adaptor', sub{ return $cas9_adaptor } );

    my $mock_cas9_prep_object_4 = Test::MockObject->new();
    my $prep_type_4 = 'protein';
    $mock_cas9_prep_object_4->set_isa( 'Crispr::DB::Cas9Prep' );
    $mock_cas9_prep_object_4->mock( 'db_id', sub{ return 4 } );
    $mock_cas9_prep_object_4->mock( 'cas9', sub{ return $mock_cas9_object_2 } );
    $mock_cas9_prep_object_4->mock( 'prep_type', sub{ return $prep_type_4 } );
    $mock_cas9_prep_object_4->mock( 'made_by', sub{ return 'cr_test2' } );
    $mock_cas9_prep_object_4->mock( 'date', sub{ return $todays_date_obj->ymd } );
    $mock_cas9_prep_object_4->mock( 'type', sub{ return $mock_cas9_object_2->type } );
    $mock_cas9_prep_object_4->mock( 'notes', sub{ return 'some different notes' } );
    #$mock_cas9_prep_object_4->mock( 'cas9_adaptor', sub{ return $cas9_adaptor } );

    # make a new real Cas9Prep Adaptor
    my $cas9_prep_adaptor = Crispr::DB::Cas9PrepAdaptor->new(
        db_connection => $mock_db_connection,
        cas9_adaptor => $cas9_adaptor,
    );
    # 1 test
    isa_ok( $cas9_prep_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: check object class is ok" );
    
    # check attributes and methods exist 3 + 18 tests
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
       table => 'cas9_prep',
       where => [ cas9_prep_id => 1 ],
       tests => {
           'eq' => {
                cas9_id => $mock_cas9_prep_object_1->cas9->db_id,
                prep_type => $mock_cas9_prep_object_1->prep_type,
                made_by  => $mock_cas9_prep_object_1->made_by,
                date => $mock_cas9_prep_object_1->date,
           },
       },
       label => "$driver: cas9_prep stored",
    );
        

    throws_ok { $cas9_prep_adaptor->store_cas9_prep('Cas9PrepObject') }
        qr/Argument\smust\sbe\sCrispr::DB::Cas9Prep\sobject/, "$driver: store_cas9_prep throws on string input";
    my $regex = $driver eq 'mysql' ?   qr/Duplicate\sentry/xms
        :                           qr/PRIMARY\sKEY\smust\sbe\sunique/xms;
    
    throws_ok { $cas9_prep_adaptor->store_cas9_prep( $mock_cas9_prep_object_1) }
        $regex, "$driver: store_cas9_prep throws because of duplicate entry";
    ok( $cas9_prep_adaptor->store_cas9_prep( $mock_cas9_prep_object_2 ), "$driver: store_cas9_prep" );
    row_ok(
       table => 'cas9_prep',
       where => [ cas9_prep_id => 2 ],
       tests => {
           'eq' => {
                cas9_id => $mock_cas9_prep_object_2->cas9->db_id,
                prep_type => $mock_cas9_prep_object_2->prep_type,
                made_by  => $mock_cas9_prep_object_2->made_by,
                date => $mock_cas9_prep_object_2->date,
           },
       },
       label => "$driver: cas9_prep 2 stored",
    );

    throws_ok { $cas9_prep_adaptor->store_cas9_preps('Cas9PrepObject') }
        qr/Supplied\sargument\smust\sbe\san\sArrayRef\sof\sCas9Prep\sobjects/,
        "$driver: store_cas9_preps throws on non ARRAYREF";
    throws_ok { $cas9_prep_adaptor->store_cas9_preps( [ 'Cas9PrepObject' ] ) }
        qr/Argument\smust\sbe\sCrispr::DB::Cas9Prep\sobject/,
        "$driver: store_cas9_preps throws on string input";
    
    ok( $cas9_prep_adaptor->store_cas9_preps( [ $mock_cas9_prep_object_3, $mock_cas9_prep_object_4 ] ), "$driver: store_cas9_preps" );
    row_ok(
       table => 'cas9_prep',
       where => [ cas9_prep_id => 3 ],
       tests => {
           'eq' => {
                cas9_id => $mock_cas9_prep_object_3->cas9->db_id,
                prep_type => $mock_cas9_prep_object_3->prep_type,
                made_by  => $mock_cas9_prep_object_3->made_by,
                date => $mock_cas9_prep_object_3->date,
           },
       },
       label => "$driver: cas9_prep 3 stored",
    );
    row_ok(
       table => 'cas9_prep',
       where => [ cas9_prep_id => 4 ],
       tests => {
           'eq' => {
                cas9_id => $mock_cas9_prep_object_4->cas9->db_id,
                prep_type => $mock_cas9_prep_object_4->prep_type,
                made_by  => $mock_cas9_prep_object_4->made_by,
                date => $mock_cas9_prep_object_4->date,
           },
       },
       label => "$driver: cas9_prep 4 stored",
    );

    # fetch methods
    my $cas9_from_db_1;
    my $mock_cas9_prep_object_5 = Test::MockObject->new();
    my $prep_type_5 = 'rna';
    $mock_cas9_prep_object_5->set_isa( 'Crispr::DB::Cas9Prep' );
    $mock_cas9_prep_object_5->mock( 'db_id', sub{ return 5 } );
    $mock_cas9_prep_object_5->mock( 'cas9', sub{ return $mock_cas9_object } );
    $mock_cas9_prep_object_5->mock( 'prep_type', sub{ return $prep_type_5 } );
    $mock_cas9_prep_object_5->mock( 'made_by', sub{ return 'cr_test2' } );
    $mock_cas9_prep_object_5->mock( 'date', sub{ return $todays_date_obj->ymd } );
    $mock_cas9_prep_object_5->mock( 'type', sub{ return $mock_cas9_object->type } );
    $mock_cas9_prep_object_5->mock( 'notes', sub{ return 'some notes' } );
    my $mock_cas9_prep_object_6 = Test::MockObject->new();
    my $prep_type_6 = 'protein';
    $mock_cas9_prep_object_6->set_isa( 'Crispr::DB::Cas9Prep' );
    $mock_cas9_prep_object_6->mock( 'db_id', sub{ return 6 } );
    $mock_cas9_prep_object_6->mock( 'cas9', sub{ return $mock_cas9_object } );
    $mock_cas9_prep_object_6->mock( 'prep_type', sub{ return $prep_type_6 } );
    $mock_cas9_prep_object_6->mock( 'made_by', sub{ return 'cr_test2' } );
    $mock_cas9_prep_object_6->mock( 'date', sub{ return $todays_date_obj->ymd } );
    $mock_cas9_prep_object_6->mock( 'type', sub{ return $mock_cas9_object->type } );
    $mock_cas9_prep_object_6->mock( 'notes', sub{ return 'some notes' } );

    # _make_new_cas9_prep_from_db - 9 tests
    ok( $cas9_from_db_1 = $cas9_prep_adaptor->_make_new_cas9_prep_from_db(
        [ 5, 'rna', 'cr_test2', $todays_date_obj->ymd, 'some notes', 1,
            $mock_cas9_prep_object_5->cas9->name, $mock_cas9_prep_object_5->cas9->type,
            $mock_cas9_prep_object_5->cas9->vector, $mock_cas9_prep_object_5->cas9->species, ]
    ), '_make_new_cas9_prep_from_db');
    check_attributes( $cas9_from_db_1, $mock_cas9_prep_object_5, $driver, '_make_new_cas9_prep_from_db' );
    
    # _make_new_object_from_db - 9 tests
    ok( $cas9_from_db_1 = $cas9_prep_adaptor->_make_new_object_from_db(
        [ 6, 'protein', 'cr_test2', $todays_date_obj->ymd, 'some notes', 1,
            $mock_cas9_prep_object_6->cas9->name, $mock_cas9_prep_object_6->cas9->type,
            $mock_cas9_prep_object_6->cas9->vector, $mock_cas9_prep_object_6->cas9->species, ]
    ), '_make_new_cas9_prep_from_db');
    check_attributes( $cas9_from_db_1, $mock_cas9_prep_object_6, $driver, '_make_new_object_from_db' );
    
    # fetch_by_id - 9 tests
    throws_ok{ $cas9_prep_adaptor->fetch_by_id( 10 ) } qr/Couldn't retrieve cas9_prep/, "$driver: Cas9prep does not exist in db";
    
    SKIP: {
        my $cas9_from_db = $cas9_prep_adaptor->fetch_by_id( 1 );
        
        skip "No cas9 returned from db!", 8 if !$cas9_from_db;
        # test attributes
        check_attributes( $cas9_from_db, $mock_cas9_prep_object_1, $driver, 'fetch_by_id' );
    }
    
    # fetch_by_ids - 16 tests
    SKIP:{
        my $cas9_objects_from_db = $cas9_prep_adaptor->fetch_by_ids( [ 3, 4 ] );
        
        skip "No cas9 objects returned from db!", 16 if !defined $cas9_objects_from_db->[0];
        my @cas9_preps = ( $mock_cas9_prep_object_3, $mock_cas9_prep_object_4 );
        foreach my $i ( 0..1 ){
            my $cas9_from_db = $cas9_objects_from_db->[$i];
            my $prep = $cas9_preps[$i];
            check_attributes( $cas9_from_db, $prep, $driver, 'fetch_by_ids' );
        }
    }
    
    # check other fetch methods - 10 test
    my $cas9_preps;
    ok( $cas9_preps = $cas9_prep_adaptor->fetch_all_by_type_and_date( 'ZfnCas9n', $todays_date_obj->ymd ), "$driver: fetch_all_by_type_and_date");
    is( scalar @{$cas9_preps}, 2, "$driver: check number returned by type and date");
    ok( $cas9_preps = $cas9_prep_adaptor->fetch_all_by_type( 'ZfnCas9-D10An' ), "$driver: fetch_all_by_type");
    is( scalar @{$cas9_preps}, 2, "$driver: check number returned by fetch_all_by_type");
    ok( $cas9_preps = $cas9_prep_adaptor->fetch_all_by_date( $todays_date_obj->ymd ), "$driver: fetch_all_by_date");
    is( scalar @{$cas9_preps}, 4, "$driver: check number returned by date");
    ok( $cas9_preps = $cas9_prep_adaptor->fetch_all_by_made_by( 'cr_test' ), "$driver: fetch_all_by_made_by");
    is( scalar @{$cas9_preps}, 2, "$driver: check number returned by fetch_all_by_made_by");
    ok( $cas9_preps = $cas9_prep_adaptor->fetch_all_by_prep_type( 'rna' ), "$driver: fetch_all_by_prep_type");
    is( scalar @{$cas9_preps}, 2, "$driver: check number returned by fetch_all_by_prep_type");
    
    #TODO 1 tests
TODO: {
    local $TODO = 'methods not implemented yet.';
    
    ok( $cas9_prep_adaptor->delete_cas9_prep_from_db ( 'rna' ), 'delete_cas9_prep_from_db');
}
    $db_connection->destroy;
    
}

sub check_attributes {
    my ( $object1, $object2, $driver, $method ) = @_;
    is( $object1->db_id, $object2->db_id, "$driver: object from db - check db_id - $method");
    is( $object1->prep_type, $object2->prep_type, "$driver: object from db - check prep_type - $method");
    is( $object1->made_by, $object2->made_by, "$driver: object from db - check made_by - $method");
    is( $object1->date, $object2->date, "$driver: object from db - check date - $method");
    is( $object1->notes, $object2->notes, "$driver: object from db - check notes - $method");
    is( $object1->cas9->db_id, $object2->cas9->db_id, "$driver: object from db - check db_id - $method");
    is( $object1->cas9->type, $object2->cas9->type, "$driver: object from db - check type - $method");
    is( $object1->cas9->name, $object2->cas9->name, "$driver: object from db - check name - $method");
}
