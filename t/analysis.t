#!/usr/bin/env perl
# analysis.t
use strict; use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use DateTime;

my $tests;

use Crispr::DB::Analysis;

# make new object with no attributes
my $analysis = Crispr::DB::Analysis->new();

isa_ok( $analysis, 'Crispr::DB::Analysis');
$tests++;

# check attributes and methods - 2 tests
my @attributes = (
    qw{ db_id plex info analysis_started analysis_finished}
);

my @methods = ( qw{ samples amplicons } );

foreach my $attribute ( @attributes ) {
    can_ok( $analysis, $attribute );
    $tests++;
}
foreach my $method ( @methods ) {
    can_ok( $analysis, $method );
    $tests++;
}

# check default attributes
my $db_id = undef;
is( $analysis->db_id, $db_id, 'check db_id default');
$tests++;

use lib 't/lib';
use TestMethods;
my $test_method_obj = TestMethods->new();

# make mock objects
my $args = {
    add_to_db => 0,
};
my ( $mock_plex, $mock_plex_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'plex', $args, );
my ( $mock_cas9, $mock_cas9_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'cas9', $args, );
$args->{mock_cas9_object} = $mock_cas9;
my ( $mock_cas9_prep, $mock_cas9_prep_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'cas9_prep', $args, );
my ( $mock_target, $mock_target_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'target', $args, );
my ( $mock_plate, $mock_plate_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'plate', $args, );
$args->{mock_target} = $mock_target;
$args->{mock_plate} = $mock_plate;
my ( $mock_well, $mock_well_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'well', $args, );
$args->{mock_well} = $mock_well;
$args->{crRNA_num} = 1;
my ( $mock_crRNA_1, $mock_crRNA_1_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'crRNA', $args, );
$mock_well->mock('position', sub { return 'A02' } );
$args->{mock_target} = $mock_target;
$args->{crRNA_num} = 2;
my ( $mock_crRNA_2, $mock_crRNA_2_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'crRNA', $args, );
$args->{mock_crRNA} = $mock_crRNA_1;
$args->{gRNA_num} = 1;
my ( $mock_gRNA_1, $mock_gRNA_1_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'gRNA', $args, );
$args->{mock_well} = $mock_well;
$args->{mock_crRNA} = $mock_crRNA_2;
$args->{gRNA_num} = 2;
my ( $mock_gRNA_2, $mock_gRNA_2_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'gRNA', $args, );
$args->{mock_cas9_prep} = $mock_cas9_prep;
$args->{mock_gRNA_1} = $mock_gRNA_1;
$args->{mock_gRNA_2} = $mock_gRNA_2;
my ( $mock_injection_pool, $mock_injection_pool_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'injection_pool', $args, );
$args->{mock_injection_pool} = $mock_injection_pool;
$args->{sample_ids} = [ 1..2 ];
#$args->{well_ids} = [ qw{A01 A02 A03 A04 A05 A06 A07 A08 A09 A10} ];
$args->{well_ids} = [ qw{A01 A02} ];
my ( $mock_samples, $mock_sample_ids, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'sample', $args, );
$args->{mock_samples} = $mock_samples;
$args->{barcode_ids} = [ 1..2 ];
my ( $mock_left_primer, $mock_left_primer_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'primer', $args, );
$args->{mock_left_primer} = $mock_left_primer;
my ( $mock_right_primer, $mock_right_primer_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'primer', $args, );
$args->{mock_right_primer} = $mock_right_primer;
my ( $mock_primer_pair, $mock_primer_pair_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'primer_pair', $args, );
$args->{mock_primer_pair} = $mock_primer_pair;
my ( $mock_sample_amplicons, $mock_sample_amplicon_ids, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'sample_amplicon', $args, );

$analysis = Crispr::DB::Analysis->new(
    db_id => 1,
    plex => $mock_plex,
    info => $mock_sample_amplicons,
    analysis_started => '2014-09-30',
    analysis_finished => '2014-10-01',
);

# check methods
my @samples = $analysis->samples;
is( scalar @samples, 2, 'check number of samples returned by samples' );
$tests++;
my @primer_pairs = $analysis->amplicons;
is( scalar @primer_pairs, 1, 'check number of amplicons returned by amplicons' );
$tests++;

is( $analysis->injection_pool->pool_name, 170, 'Check injection pool name' );
$tests++;

done_testing( $tests );
