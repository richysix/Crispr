#!/usr/bin/env perl
# primer.t
use warnings;
use strict;

use Test::More;
use Test::Exception;

plan tests => 1 + 16 + 5 + 1 + 3;

use Crispr::Primer;

# make a new primer object
my $primer = Crispr::Primer->new(
    primer_name => '5:2403050-2403073:-1',
    seq_region => '5',
    seq_region_start => 2403050,
    seq_region_end => 2403073,
    seq_region_strand => '1',
    sequence => 'ACGATGACAGATAGACAGAAGTCG',
);

# 1 test
isa_ok( $primer, 'Crispr::Primer');

# test attributes - 16 tests
my @attributes = qw( sequence primer_name seq_region seq_region_strand seq_region_start
    seq_region_end index_pos length self_end penalty
    self_any end_stability tm gc_percent
    primer_id well
);

# test methods - 5 tests
my @methods = qw(
    seq primer_summary primer_info primer_posn _build_primer_name
);

foreach my $method ( @attributes, @methods ) {
    can_ok( $primer, $method );
}


# mock objects
# make a mock plate and well
use lib 't/lib';
use TestMethods;

my $test_method_obj = TestMethods->new();
my $args = {
    add_to_db => 0,
};
my ( $mock_plate, $mock_plate_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'plate', $args, );
$args->{mock_plate} = $mock_plate;
my ( $mock_well, $mock_well_id, ) =
    $test_method_obj->create_mock_object_and_add_to_db( 'well', $args, );

# add mock well - 1 test
ok( $primer->well( $mock_well ), 'check adding well object' );

# check type constraints - 3 tests
throws_ok { Crispr::Primer->new( seq_region_strand => '2' ) }
    qr/Validation failed/ms, 'strand not 1 or -1';
throws_ok { Crispr::Primer->new( sequence => 'ACGATAGATJGACGATA' ) }
    qr/Validation\sfailed./ms, 'not DNA';
throws_ok { Crispr::Primer->new( well => '2' ) }
    qr/Validation failed/ms, 'Well not well object';

