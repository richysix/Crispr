#!/usr/bin/env perl
# primer_pair.t
use Test::More;
use Test::Exception;
use Test::MockObject;

plan tests => 1 + 18 + 1;

use Crispr::PrimerPair;

# make 2 mock Primer objects
my $mock_l_primer = Test::MockObject->new();
$mock_l_primer->mock('amplicon_name', sub { return '5:2403050-2403073:1' } );
$mock_l_primer->mock('seq_region', sub { return '5'} );
$mock_l_primer->mock('seq_region_start', sub { return 2403050 } );
$mock_l_primer->mock('seq_region_end', sub { return 2403073 } );
$mock_l_primer->mock('seq_region_strand', sub { return '1' } );
$mock_l_primer->mock('sequence', sub { return 'ACGATGACAGATAGACAGAAGTCG' } );
$mock_l_primer->set_isa('Crispr::Primer');

my $mock_r_primer = Test::MockObject->new();
$mock_r_primer->mock('amplicon_name', sub { return '5:2403250-2403273:-1' } );
$mock_r_primer->mock('seq_region', sub { return '5'} );
$mock_r_primer->mock('seq_region_start', sub { return 2403250 } );
$mock_r_primer->mock('seq_region_end', sub { return 2403273 } );
$mock_r_primer->mock('seq_region_strand', sub { return '-1' } );
$mock_r_primer->mock('sequence', sub { return 'AGATAGACTAGACATTCAGATCAG' } );
$mock_r_primer->set_isa('Crispr::Primer');

# make a new primer object
my $primer_pair = Crispr::PrimerPair->new(
    amplicon_name => 'ENSDARE00000001',
    pair_name => '5:2403050-2403273',
    product_size => '224',
    left_primer => $mock_l_primer,
    right_primer => $mock_r_primer,
    type => 'ext',
);

# 1 test
isa_ok( $primer_pair, 'Crispr::PrimerPair');

# test methods - 18 tests
my @methods = qw(  pair_name amplicon_name warnings target explain
    product_size_range excluded_regions product_size query_slice_start query_slice_end
    left_primer right_primer type pair_compl_end pair_compl_any
    pair_penalty primer_pair_summary primer_pair_info
);

foreach my $method ( @methods ) {
    can_ok( $primer_pair, $method );
}

# check type constraints - 1 tests
throws_ok { Crispr::PrimerPair->new( type => 'nt' ) }
    qr/PrimerPair:Type/ms, 'wrong pair type';

