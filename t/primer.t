#!/usr/bin/env perl
# primer.t
use Test::More;
use Test::Exception;

plan tests => 1 + 14 + 2;

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

# test methods - 14 tests
my @methods = qw( sequence primer_name seq_region seq_region_strand seq_region_start
    seq_region_end index_pos length self_end penalty
    self_any end_stability tm gc_percent
);

foreach my $method ( @methods ) {
    can_ok( $primer, $method );
}

# check type constraints - 2 tests
throws_ok { Crispr::Primer->new( seq_region_strand => '2' ) }
    qr/Validation failed/ms, 'strand not 1 or -1';
throws_ok { Crispr::Primer->new( sequence => 'ACGATAGATJGACGATA' ) }
    qr/Validation\sfailed./ms, 'not DNA';

