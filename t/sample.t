#!/usr/bin/env perl
# sample.t
use warnings;
use strict;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use DateTime;

my $tests;

# module with some methods in for creating mock objects
use lib 't/lib';
use TestMethods;
my $test_method_obj = TestMethods->new();

use Crispr::DB::Sample;

# make new object with no attributes
my $sample = Crispr::DB::Sample->new();

isa_ok( $sample, 'Crispr::DB::Sample');
$tests++;

# check attributes and methods - 11 + 1 tests
my @attributes = (
    qw{ db_id injection_pool generation sample_type sample_number
    sample_alleles total_reads species well cryo_box
    sample_name }
);

my @methods = ( qw{ add_allele } );

foreach my $attribute ( @attributes ) {
    can_ok( $sample, $attribute );
    $tests++;
}
foreach my $method ( @methods ) {
    can_ok( $sample, $method );
    $tests++;
}

# check default attributes
my $db_id = undef;
is( $sample->db_id, $db_id, 'check db_id default');
$tests++;

# make mock InjectionPool and Subplex object
my $args = {
    add_to_db => 0,
};
my ( $mock_injection_pool, $mock_injection_pool_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'injection_pool', $args, undef, );
my ( $mock_well, $mock_well_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'well', $args, undef, );

# make mock allele objects
my $allele_db_id = 1;
my $chr = '15';
my $pos = 234465;
my $ref_allele = 'G';
my $alt_allele = 'GTAGAGC';
my $mock_allele_object = Test::MockObject->new();
$mock_allele_object->set_isa( 'Crispr::Allele' );
$mock_allele_object->mock( 'db_id', sub{ return $allele_db_id } );
$mock_allele_object->mock( 'chr', sub{ return $chr } );
$mock_allele_object->mock( 'pos', sub{ return $pos } );
$mock_allele_object->mock( 'ref_allele', sub{ return $ref_allele } );
$mock_allele_object->mock( 'alt_allele', sub{ return $alt_allele } );
$mock_allele_object->mock( 'allele_name', sub{ return join(":", $chr, $pos, $ref_allele, $alt_allele ); } );

my $mock_allele2_object = Test::MockObject->new();
$mock_allele2_object->set_isa( 'Crispr::Allele' );
$mock_allele2_object->mock( 'db_id', sub{ return $allele_db_id } );
$mock_allele2_object->mock( 'chr', sub{ return $chr } );
$mock_allele2_object->mock( 'pos', sub{ return $pos } );
$mock_allele2_object->mock( 'ref_allele', sub{ return $ref_allele } );
$mock_allele2_object->mock( 'alt_allele', sub{ return $alt_allele } );
$mock_allele2_object->mock( 'allele_name', sub{ return join(":", $chr, $pos, $ref_allele, 'GTAGAG' ); } );

my $pc = 15.4;
my $mock_sample_allele = Test::MockObject->new();
$mock_sample_allele->set_isa( 'Crispr::DB::SampleAllele' );
$mock_sample_allele->mock( 'sample', sub{ return $sample } );
$mock_sample_allele->mock( 'allele', sub{ return $mock_allele_object } );
$mock_sample_allele->mock( 'percent_of_reads', sub{ return $pc } );

$sample = Crispr::DB::Sample->new(
    db_id => 1,
    injection_pool => $mock_injection_pool,
    generation => 'G0',
    sample_type => 'sperm',
    sample_number => 1,
    species => 'zebrafish',
    sample_alleles => [ $mock_sample_allele ],
    well => $mock_well,
    cryo_box => 'Cr_Sperm12'
);

is( $sample->db_id, 1, 'check db_id');
is( $sample->generation, 'G0', 'check generation');
is( $sample->sample_type, 'sperm', 'check sample_type');
is( $sample->sample_number, 1, 'check sample number');
is( $sample->well->position, 'A01', 'check well');
is( $sample->cryo_box, 'Cr_Sperm12', 'check cryo_box');
$tests += 6;

# check sample_name
is( $sample->sample_name, '170_1', 'check sample name' );
$tests++;

# check default sample_name
my $tmp_sample = Crispr::DB::Sample->new(
    db_id => 1,
    generation => 'G0',
    sample_type => 'sperm',
    sample_number => 1,
    species => 'zebrafish',
    well => undef,
    cryo_box => undef
);
is( $tmp_sample->sample_name, undef, 'check sample name: no injection_pool' );
$tests++;

$tmp_sample = Crispr::DB::Sample->new(
    db_id => 1,
    injection_pool => $mock_injection_pool,
    generation => 'G0',
    sample_type => 'sperm',
    sample_number => 1,
    species => 'zebrafish',
    well => undef,
    cryo_box => undef
);
is( $tmp_sample->sample_name, '170_1', 'check sample name: no well' );
$tests++;

$tmp_sample = Crispr::DB::Sample->new(
    db_id => 1,
    injection_pool => $mock_injection_pool,
    generation => 'G0',
    sample_type => 'sperm',
    species => 'zebrafish',
    well => undef,
    cryo_box => undef
);
is( $tmp_sample->sample_name, undef, 'check sample name: no well or sample number' );
$tests++;

throws_ok{ $sample->sample_alleles( [ $mock_allele_object ] ) }
    qr/Cannot assign a value to a read-only accessor/,
    'throws on attempt to set alleles attribute';
is( scalar @{$sample->sample_alleles}, 1, 'check number of sample alleles 1');
ok( $sample->add_allele( $mock_allele2_object, 10.4 ), 'test add allele method');
is( scalar @{$sample->sample_alleles}, 2, 'check number of alleles 2');
warning_like { $sample->add_allele( $mock_allele2_object, 10.4 ) }
    qr/add_allele: ALLELE.*has already been added. Skipping.../,
    'check add_alleles warns on duplicate allele';
is( scalar @{$sample->sample_alleles}, 2, 'check number of alleles 3');
$tests+=6;


done_testing( $tests );
