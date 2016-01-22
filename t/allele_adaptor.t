#!/usr/bin/env perl
# allele_adaptor.t
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
use English qw( -no_match_vars );

use Crispr::DB::AlleleAdaptor;
use Crispr::DB::DBConnection;

# Number of tests
Readonly my $TESTS_IN_COMMON => 1 + 23 + 2 + 6 + 5 + 2 + 9 + 1 + 6 + 6 + 12 + 7 + 7 + 1 + 8 + 8 + 1;
Readonly my %TESTS_FOREACH_DBC => (
    mysql => $TESTS_IN_COMMON,
    sqlite => $TESTS_IN_COMMON,
);
if( $ENV{NO_DB} ) {
    plan skip_all => 'Not testing database';
}
else {
    plan tests => $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite};
}

# check attributes and methods - 4 + 19 tests
my @attributes = ( qw{ dbname db_connection connection crRNA_adaptor } );

my @methods = (
    qw{ store store_allele store_alleles store_crisprs_for_allele allele_exists_in_db
    fetch_by_id fetch_by_ids fetch_by_allele_number fetch_by_variant_description fetch_all_by_crispr
    fetch_all_by_sample get_db_id_by_variant_description _fetch _make_new_allele_from_db delete_allele_from_db
    check_entry_exists_in_db fetch_rows_expecting_single_row fetch_rows_for_generic_select_statement _db_error_handling }
);

# DB tests
# Module with a function for creating an empty test database
# and returning a database connection
use lib 't/lib';
use TestMethods;

my $test_method_obj = TestMethods->new();
my ( $db_connection_params, $db_connections ) = $test_method_obj->create_test_db();

SKIP: {
    skip 'No database connections available', $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite} if !@{$db_connections};

    if( @{$db_connections} == 1 ){
        skip 'Only one database connection available', $TESTS_FOREACH_DBC{sqlite} if $db_connections->[0]->driver eq 'mysql';
        skip 'Only one database connection available', $TESTS_FOREACH_DBC{mysql} if $db_connections->[0]->driver eq 'sqlite';
    }
}

foreach my $db_connection ( @{$db_connections} ){
    my $driver = $db_connection->driver;
    my $dbh = $db_connection->connection->dbh;
    # $dbh is a DBI database handle
    local $Test::DatabaseRow::dbh = $dbh;

    # make a real DBConnection object
    my $db_conn = Crispr::DB::DBConnection->new( $db_connection_params->{$driver} );

    # make a new real Allele Adaptor
    my $allele_adaptor = Crispr::DB::AlleleAdaptor->new( db_connection => $db_conn, );
    # 1 test
    isa_ok( $allele_adaptor, 'Crispr::DB::AlleleAdaptor', "$driver: check object class is ok" );

    # check attributes and methods exist 4 + 19 tests
    foreach my $attribute ( @attributes ) {
        can_ok( $allele_adaptor, $attribute );
    }
    foreach my $method ( @methods ) {
        can_ok( $allele_adaptor, $method );
    }

    # mock objects
    my $args = {
        add_to_db => 1,
    };
    my ( $mock_plex, $mock_plex_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'plex', $args, $db_connection, );
    my ( $mock_cas9, $mock_cas9_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'cas9', $args, $db_connection, );
    $args->{mock_cas9_object} = $mock_cas9;
    my ( $mock_cas9_prep, $mock_cas9_prep_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'cas9_prep', $args, $db_connection, );
    my ( $mock_target, $mock_target_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'target', $args, $db_connection, );
    my ( $mock_plate, $mock_plate_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'plate', $args, $db_connection, );
    $args->{mock_target} = $mock_target;
    $args->{crRNA_num} = 1;
    my ( $mock_crRNA_1, $mock_crRNA_1_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'crRNA', $args, $db_connection, );
    $args->{mock_target} = $mock_target;
    $args->{crRNA_num} = 2;
    my ( $mock_crRNA_2, $mock_crRNA_2_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'crRNA', $args, $db_connection, );
    $args->{mock_plate} = $mock_plate;
    my ( $mock_well, $mock_well_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'well', $args, $db_connection, );
    $args->{mock_well} = $mock_well;
    $args->{mock_crRNA} = $mock_crRNA_1;
    $args->{gRNA_num} = 1;
    my ( $mock_gRNA_1, $mock_gRNA_1_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'gRNA', $args, $db_connection, );
    $args->{mock_well} = $mock_well;
    $args->{mock_crRNA} = $mock_crRNA_2;
    $args->{gRNA_num} = 2;
    my ( $mock_gRNA_2, $mock_gRNA_2_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'gRNA', $args, $db_connection, );
    $args->{mock_cas9_prep} = $mock_cas9_prep;
    $args->{mock_gRNA_1} = $mock_gRNA_1;
    $args->{mock_gRNA_2} = $mock_gRNA_2;
    my ( $mock_injection_pool, $mock_injection_pool_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'injection_pool', $args, $db_connection, );
    $args->{mock_injection_pool} = $mock_injection_pool;
    my ( $mock_sample, $mock_sample_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'sample', $args, $db_connection, );

    my ( $statement, $sth );

    # make a mock allele
    my $allele_id = 1;
    my $allele_number = 10;
    my $mock_allele = Test::MockObject->new();
    $mock_allele->set_isa('Crispr::Allele');
    $mock_allele->mock('db_id', sub { return $allele_id } );
    $mock_allele->mock('allele_number', sub { return $allele_number } );
    $mock_allele->mock('chr', sub { return 'Zv9_scaffold12' } );
    $mock_allele->mock('pos', sub { return 256738 } );
    $mock_allele->mock('ref_allele', sub { return 'ACGTA' } );
    $mock_allele->mock('alt_allele', sub { return 'A' } );
    $mock_allele->mock('crisprs', sub{ return [ $mock_crRNA_1 ]; } );
    $mock_allele->mock('percent_of_reads', sub{ return 11.4; } );

    # check db adaptor attributes - 2 tests
    my $crRNA_adaptor;
    ok( $crRNA_adaptor = $allele_adaptor->crRNA_adaptor(), "$driver: get crRNA_adaptor" );
    isa_ok( $crRNA_adaptor, 'Crispr::DB::crRNAAdaptor', "$driver: check crRNA_adaptor class" );
    # my $sample_adaptor;
    # ok( $sample_adaptor = $allele_adaptor->sample_adaptor(), "$driver: get sample_adaptor" );
    # isa_ok( $sample_adaptor, 'Crispr::DB::SampleAdaptor', "$driver: check sample_adaptor class" );

    # check store methods 6 tests
    ok( $allele_adaptor->store( $mock_allele ), "$driver: store" );
    row_ok(
       table => 'allele',
       where => [ allele_id => 1 ],
       tests => {
           '==' => {
                pos => $mock_allele->pos,
                allele_number => $mock_allele->allele_number,
           },
           'eq' => {
               chr => $mock_allele->chr,
               ref_allele => $mock_allele->ref_allele,
               alt_allele => $mock_allele->alt_allele,
           },
       },
       label => "$driver: allele stored",
    );
    row_ok(
       table => 'allele_to_crispr',
       where => [ allele_id => 1 ],
       tests => {
           '==' => {
                crRNA_id => 1,
           },
       },
       label => "$driver: check crisprs stored for allele",
    );
    
    # test that store throws properly
    throws_ok { $allele_adaptor->store_allele('Allele') }
        qr/Argument\smust\sbe\sCrispr::Allele\sobject/,
        "$driver: store_allele throws on string input";
    throws_ok { $allele_adaptor->store_allele($mock_cas9) }
        qr/Argument\smust\sbe\sCrispr::Allele\sobject/,
        "$driver: store_allele throws if object is not Crispr::DB::Allele";
    $allele_id++;
    $allele_number++;
    # check throws ok on attempted duplicate entry
    # for this we need to suppress the warning that is generated as well, hence the nested warning_like test
    # This does not affect the apparent number of tests run
    my $regex = $driver eq 'mysql' ?   qr/Duplicate\sentry/xms
        :                           qr/unique/xmsi;
    
    throws_ok {
        warning_like { $allele_adaptor->store_allele($mock_allele) }
            $regex;
    }
        $regex, "$driver: store_allele throws on duplicate variant";

    # store allele - 5 tests
    # change alt allele to stop db throwing on store
    $mock_allele->mock('alt_allele', sub { return 'C' } );
    ok( $allele_adaptor->store_allele( $mock_allele ), "$driver: store_allele" );
    row_ok(
       table => 'allele',
       where => [ allele_id => 2 ],
       tests => {
           '==' => {
                pos => $mock_allele->pos,
                allele_number => $mock_allele->allele_number,
           },
           'eq' => {
               chr => $mock_allele->chr,
               ref_allele => $mock_allele->ref_allele,
               alt_allele => $mock_allele->alt_allele,
           },
       },
       label => "$driver: allele stored",
    );
    row_ok(
       table => 'allele_to_crispr',
       where => [ allele_id => 1 ],
       tests => {
           '==' => {
                crRNA_id => 1,
           },
       },
       label => "$driver: check crisprs stored for allele",
    );

    throws_ok { $allele_adaptor->store_alleles('AlleleObject') }
        qr/Supplied\sargument\smust\sbe\san\sArrayRef\sof\sAllele\sobjects/,
        "$driver: store_alleles throws on non ARRAYREF";
    throws_ok { $allele_adaptor->store_alleles( [ 'AlleleObject' ] ) }
        qr/Argument\smust\sbe\sCrispr::Allele\sobject/,
        "$driver: store_alleles throws on string input";

    # make new mock object for store alleles
    my $mock_allele_2 = Test::MockObject->new();
    $mock_allele_2->set_isa( 'Crispr::Allele' );
    $mock_allele_2->mock( 'db_id', sub{ return 4 } );
    $mock_allele_2->mock('allele_number', sub { return 20 } );
    $mock_allele_2->mock('chr', sub { return 'Zv9_scaffold12' } );
    $mock_allele_2->mock('pos', sub { return 256738 } );
    $mock_allele_2->mock('ref_allele', sub { return 'GCGTA' } );
    $mock_allele_2->mock('alt_allele', sub { return 'G' } );
    $mock_allele_2->mock('crisprs', sub{ return [ $mock_crRNA_1, $mock_crRNA_2 ]; } );

    # check allele_exists_in_db - 2 tests
    is( $allele_adaptor->allele_exists_in_db( $mock_allele ),
        1, "$driver: allele_exists_in_db 1");
    is( $allele_adaptor->allele_exists_in_db( $mock_allele_2 ),
        undef, "$driver: allele_exists_in_db 2");
    
    # 9 tests
    # increment mock object 1's id
    $allele_id++;
    $allele_number++;
    # and change variant
    $mock_allele->mock('alt_allele', sub { return 'G' } );
    ok( $allele_adaptor->store_alleles( [ $mock_allele, $mock_allele_2 ] ), "$driver: store_alleles" );
    row_ok(
       table => 'allele',
       where => [ allele_id => 3 ],
       tests => {
           '==' => {
                pos => $mock_allele->pos,
                allele_number => $mock_allele->allele_number,
           },
           'eq' => {
               chr => $mock_allele->chr,
               ref_allele => $mock_allele->ref_allele,
               alt_allele => $mock_allele->alt_allele,
           },
       },
       label => "$driver: allele stored",
    );
    row_ok(
       table => 'allele_to_crispr',
       where => [ allele_id => 3 ],
       tests => {
           '==' => {
                crRNA_id => 1,
           },
       },
       label => "$driver: check crisprs stored for allele",
    );
    # allele 2
    row_ok(
       table => 'allele',
       where => [ allele_id => 4 ],
       tests => {
           '==' => {
                pos => $mock_allele_2->pos,
                allele_number => $mock_allele_2->allele_number,
           },
           'eq' => {
               chr => $mock_allele_2->chr,
               ref_allele => $mock_allele_2->ref_allele,
               alt_allele => $mock_allele_2->alt_allele,
           },
       },
       label => "$driver: allele stored",
    );
    my @rows;
    row_ok(
        sql => "SELECT * FROM allele_to_crispr WHERE allele_id = 4;",
        store_rows => \@rows,
        label => "$driver: allele_to_crispr for allele 4",
    );
    #my @rows = sort { $_->[1] } @rows;
    my @expected_results = (
        [ 4, 1 ],
        [ 4, 2 ],
    );
    foreach my $row ( @rows ){
        my $ex = shift @expected_results;
        is( $row->{allele_id}, $ex->[0], "$driver: allele_to_crispr check allele_id" );
        is( $row->{crRNA_id}, $ex->[1], "$driver: allele_to_crispr check crRNA_id" );
    }
    
    # add info to sample_allele table
    $statement = 'insert into sample_allele values ( ?, ?, ? )';
    $sth = $dbh->prepare($statement);
    $sth->execute(
        $mock_sample->db_id,
        $mock_allele->db_id,
        $mock_allele->percent_of_reads,
    );
    
    # 1 test
    throws_ok{ $allele_adaptor->fetch_by_id( 10 ) } qr/Couldn't retrieve allele/, 'Allele does not exist in db';

    # _fetch - 6 tests
    my $allele_from_db = @{ $allele_adaptor->_fetch( 'a.allele_id = ?', [ 3, ] ) }[0];
    check_attributes( $allele_from_db, $mock_allele, $driver, '_fetch', );

    # fetch_by_id - 6 tests
    $allele_from_db = $allele_adaptor->fetch_by_id( 4 );
    check_attributes( $allele_from_db, $mock_allele_2, $driver, 'fetch_by_id', );

    # fetch_by_ids - 12 tests
    my @ids = ( 3, 4 );
    my $alleles_from_db = $allele_adaptor->fetch_by_ids( \@ids );

    my @alleles = ( $mock_allele, $mock_allele_2 );
    foreach my $i ( 0..1 ){
        my $allele_from_db = $alleles_from_db->[$i];
        my $mock_allele = $alleles[$i];
        check_attributes( $allele_from_db, $mock_allele, $driver, 'fetch_by_ids', );
    }

    # fetch_by_allele_number - 7 tests
    ok( $allele_from_db = $allele_adaptor->fetch_by_allele_number( 12 ), "$driver: fetch_by_allele_number");
    check_attributes( $allele_from_db, $mock_allele, $driver, 'fetch_by_allele_number', );

    # fetch_by_variant_description - 7 tests
    $mock_allele->mock('allele_name', sub { return 'Zv9_scaffold12:256738:ACGTA:G' } );
    ok( $allele_from_db = $allele_adaptor->fetch_by_variant_description( $mock_allele->allele_name ),
        "$driver: fetch_by_variant_description");
    check_attributes( $allele_from_db, $mock_allele, $driver, 'fetch_by_variant_description', );
    
    # get_db_id_by_variant_description - 1 tests
    $mock_allele_2->mock('allele_name', sub { return 'Zv9_scaffold12:256738:GCGTA:G' } );
    is( $allele_adaptor->get_db_id_by_variant_description( $mock_allele_2->allele_name ), 4,
        "$driver: get_db_id_by_variant_description");
    
    # fetch_all_by_crispr - 8 tests
    ok( $alleles_from_db = $allele_adaptor->fetch_all_by_crispr( $mock_crRNA_1 ), "$driver: fetch_all_by_crispr");
    is( scalar @{$alleles_from_db}, 4, "$driver: fetch_all_by_crispr - check number returned" );
    check_attributes( $alleles_from_db->[2], $mock_allele, $driver, 'fetch_all_by_crispr', );

    # fetch_all_by_sample - 8 tests
    ok( $alleles_from_db = $allele_adaptor->fetch_all_by_sample( $mock_sample ), 'fetch_all_by_sample');
    is( scalar @{$alleles_from_db}, 1, "$driver: check number returned by fetch_all_by_sample" );
    check_attributes( $alleles_from_db->[0], $mock_allele, $driver, 'fetch_all_by_sample', );
    
TODO: {
    local $TODO = 'methods not implemented yet.';
    
    ok( $allele_adaptor->delete_allele_from_db ( 'rna' ), 'delete_allele_from_db');
}

    #$db_connection->destroy();
}

# 6 tests
sub check_attributes {
    my ( $object1, $object2, $driver, $method ) = @_;
    is( $object1->db_id, $object2->db_id, "$driver: object from db $method - check db_id");
    is( $object1->allele_number, $object2->allele_number, "$driver: object from db $method - check allele_number");
    is( $object1->chr, $object2->chr, "$driver: object from db $method - check chr");
    is( $object1->pos, $object2->pos, "$driver: object from db $method - check pos");
    is( $object1->ref_allele, $object2->ref_allele, "$driver: object from db $method - check ref_allele");
    is( $object1->alt_allele, $object2->alt_allele, "$driver: object from db $method - check alt_allele");
}
