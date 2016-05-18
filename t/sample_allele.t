#!/usr/bin/env perl
# sample_allele.t
use warnings;
use strict;

use Test::More;
use Test::MockObject;
use Test::Exception;
use Test::DatabaseRow;
use Data::Dumper;
use Readonly;

use Crispr::DB::SampleAllele;
use Crispr::DB::SampleAlleleAdaptor;
use Crispr::DB::DBConnection;

Readonly my $NON_DB_TESTS => 1 + 2 + 1 + 1;
Readonly my $DB_TESTS => 1 + 1 + 6 + 2 + 2 + 2 + 14 + 14;
Readonly my %TESTS_FOREACH_DBC => (
    mysql => $DB_TESTS,
    sqlite => $DB_TESTS,
);

plan tests => $NON_DB_TESTS + $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite};

# make mock objects
use lib 't/lib';
use TestMethods;

my $test_method_obj = TestMethods->new();
my ( $db_connection_params, $db_connections );
if( !$ENV{NO_DB} ) {
    ( $db_connection_params, $db_connections ) = $test_method_obj->create_test_db();
}

# make mock objects
my $args = _create_mock_objects( 0, );

# attributes
my $percent_of_reads = 10.2;

# make new object - 1 test
my %args = (
    sample => $args->{mock_samples}->[0],
    allele => $args->{mock_allele},
    percent_of_reads => $percent_of_reads,
);

my $sample_allele = Crispr::DB::SampleAllele->new( %args );

isa_ok( $sample_allele, 'Crispr::DB::SampleAllele');

# check attributes and methods - 2 tests
my @attributes = (
    qw{ allele percent_of_reads }
);

my @methods = ();

foreach my $attribute ( @attributes ) {
    can_ok( $sample_allele, $attribute );
}
foreach my $method ( @methods ) {
    can_ok( $sample_allele, $method );
}

# check alleles attribute - 1 test
is( $sample_allele->allele->allele_number,
    $args->{mock_allele}->allele_number,
    'check alleles object allele_number attribute' );

# check percent_of_reads attribute - 1 test
is( $sample_allele->percent_of_reads,
    $percent_of_reads,
    'check percent_of_reads attribute' );

SKIP: {
    skip 'Not testing database', $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite} if $ENV{NO_DB};
    skip 'No database connections available', $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite} if !@{$db_connections};

    if( @{$db_connections} == 1 ){
        skip 'Only one database connection available', $TESTS_FOREACH_DBC{sqlite} if $db_connections->[0]->driver eq 'mysql';
        skip 'Only one database connection available', $TESTS_FOREACH_DBC{mysql} if $db_connections->[0]->driver eq 'sqlite';
    }
}

my @adaptor_attributes = ( qw{ _sample_allele_cache } );
my @adaptor_methods = ( qw{ store store_sample_allele store_sample_alleles fetch_all_by_sample _fetch
    _make_new_sample_allele_from_db } );

foreach my $db_connection ( @{$db_connections} ){
    my $driver = $db_connection->driver;
    my $dbh = $db_connection->connection->dbh;
    # $dbh is a DBI database handle
    local $Test::DatabaseRow::dbh = $dbh;

    # make a real DBConnection object
    my $db_conn = Crispr::DB::DBConnection->new( $db_connection_params->{$driver} );

    # make a new real Allele Adaptor
    my $allele_adaptor = Crispr::DB::AlleleAdaptor->new( db_connection => $db_conn, );

    # make a new real SampleAllele Adaptor
    my $sample_allele_adaptor = Crispr::DB::SampleAlleleAdaptor->new( db_connection => $db_conn, );
    # 1 test
    isa_ok( $sample_allele_adaptor, 'Crispr::DB::SampleAlleleAdaptor', "$driver: check object class is ok" );
    
    # check attributes and methods exist 1 + 6 tests
    foreach my $attribute ( @adaptor_attributes ) {
        can_ok( $sample_allele_adaptor, $attribute );
    }
    foreach my $method ( @adaptor_methods ) {
        can_ok( $sample_allele_adaptor, $method );
    }

    # add mock objects to db
    $args = _create_mock_objects( 1, $db_connection, );
    # check store methods - 2 tests
    ok( $sample_allele_adaptor->store( $sample_allele ), "$driver: store" );
    row_ok(
       table => 'sample_allele',
       where => [ sample_id => 1 ],
       tests => {
           '==' => {
                allele_id => $args->{mock_allele}->db_id,
                percentage_of_reads => $percent_of_reads,
           },
       },
       label => "$driver: sample_allele stored",
    );
    # test that store throws properly - 2 tests
    throws_ok { $sample_allele_adaptor->store_sample_allele('SampleAllele') }
        qr/Argument must be Crispr::DB::SampleAllele objects/,
        "$driver: store_allele throws on string input";
    throws_ok { $sample_allele_adaptor->store_sample_allele($args->{mock_cas9}) }
        qr/Argument must be Crispr::DB::SampleAllele objects/,
        "$driver: store_allele throws if object is not Crispr::DB::SampleAllele";
    
    # test that store throws properly - 2 tests
    throws_ok { $sample_allele_adaptor->store_sample_alleles('SampleAllele') }
        qr/Supplied argument must be an ArrayRef of SampleAllele objects/,
        "$driver: store_alleles throws on string input";
    throws_ok { $sample_allele_adaptor->store_sample_alleles( [ 'SampleAllele', ] ) }
        qr/Argument must be Crispr::DB::SampleAllele objects/,
        "$driver: store_alleles throws if object is not Crispr::DB::SampleAllele";

    # check fetch methods

    # _fetch - 14 tests
    my $sample_allele_from_db = @{ $sample_allele_adaptor->_fetch( 'sample_id = ?', [ 1, ] ) }[0];
    check_attributes( $sample_allele_from_db, $sample_allele, $driver, '_fetch', );
    
    # fetch_all_by_sample - 14 tests
    my $sample_alleles_from_db = $sample_allele_adaptor->fetch_all_by_sample( $args->{mock_samples}->[0] );
    check_attributes( $sample_alleles_from_db->[0], $sample_allele, $driver, 'fetch_all_by_sample', );
    
    $db_connection->destroy();
}

# 14 tests per call
sub check_attributes {
    my ( $object1, $object2, $driver, $method ) = @_;
    is( $object1->sample->db_id, $object2->sample->db_id, "$driver: object from db $method - check sample db_id");
    is( $object1->sample->sample_name, $object2->sample->sample_name,
        "$driver: object from db $method - check sample sample_name");
    is( $object1->sample->generation, $object2->sample->generation, "$driver: object from db $method - check sample generation");
    is( $object1->sample->sample_type, $object2->sample->sample_type, "$driver: object from db $method - check sample sample_type");
    is( $object1->sample->species, $object2->sample->species, "$driver: object from db $method - check sample species");
    is( $object1->sample->well->position, $object2->sample->well->position, "$driver: object from db $method - check sample well_id");
    is( $object1->sample->cryo_box, $object2->sample->cryo_box, "$driver: object from db $method - check sample cryo_box");

    is( $object1->allele->db_id, $object2->allele->db_id, "$driver: object from db $method - check db_id");
    is( $object1->allele->allele_number, $object2->allele->allele_number, "$driver: object from db $method - check allele_number");
    is( $object1->allele->chr, $object2->allele->chr, "$driver: object from db $method - check chr");
    is( $object1->allele->pos, $object2->allele->pos, "$driver: object from db $method - check pos");
    is( $object1->allele->ref_allele, $object2->allele->ref_allele, "$driver: object from db $method - check ref_allele");
    is( $object1->allele->alt_allele, $object2->allele->alt_allele, "$driver: object from db $method - check alt_allele");
    
    is( $object1->percent_of_reads, $object2->percent_of_reads, "$driver: object from db $method - check percent of reads");
}

sub _create_mock_objects {
    my ( $add_to_db, $db_connection, ) = @_;
    
    # mock objects
    my $args = {
        add_to_db => $add_to_db,
    };
    my ( $mock_target, $mock_target_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'target', $args, $db_connection, );
    $args->{mock_target} = $mock_target;
    my ( $mock_plate, $mock_plate_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'plate', $args,  $db_connection, );
    $args->{mock_plate} = $mock_plate;
    my ( $mock_well, $mock_well_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'well', $args,  $db_connection, );
    $args->{mock_well} = $mock_well;
    $args->{crRNA_num} = 1;
    my ( $mock_crRNA_1, $mock_crRNA_1_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'crRNA', $args,  $db_connection, );
    $args->{mock_crRNA} = $mock_crRNA_1;
    $args->{gRNA_num} = 1;
    my ( $mock_gRNA_1, $mock_gRNA_1_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'gRNA', $args,  $db_connection, );
    $args->{mock_gRNA_1} = $mock_gRNA_1;
    
    $mock_well->mock('position', sub { return 'A02' } );
    $args->{crRNA_num} = 2;
    my ( $mock_crRNA_2, $mock_crRNA_2_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'crRNA', $args, $db_connection, );
    $args->{mock_crRNA} = $mock_crRNA_2;
    $args->{gRNA_num} = 2;
    my ( $mock_gRNA_2, $mock_gRNA_2_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'gRNA', $args, $db_connection, );
    $args->{mock_gRNA_2} = $mock_gRNA_2;
    $args->{mock_crRNA} = $mock_crRNA_1;

    my ( $mock_allele, $mock_allele_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'allele', $args,  $db_connection, );
    $args->{mock_allele} = $mock_allele;
    
    my ( $mock_cas9, $mock_cas9_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'cas9', $args,  $db_connection, );
    $args->{mock_cas9_object} = $mock_cas9;
    my ( $mock_cas9_prep, $mock_cas9_prep_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'cas9_prep', $args,  $db_connection, );
    $args->{mock_cas9_prep} = $mock_cas9_prep;
    my ( $mock_injection_pool, $mock_injection_pool_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'injection_pool', $args,  $db_connection, );
    $args->{mock_injection_pool} = $mock_injection_pool;
    $args->{sample_ids} = [ 1 ];
    $args->{well_ids} = [ qw{A01} ];
    my ( $mock_samples, $mock_sample_ids, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'sample', $args,  $db_connection, );
    $args->{mock_samples} = $mock_samples;
    
    return $args;
}