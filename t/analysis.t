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

# make a mock Plex object
my $mock_plex = Test::MockObject->new();
$mock_plex->set_isa( 'Crispr::DB::Plex' );
$mock_plex->mock( 'db_id', sub { return 1 } );

# make mock Sample Amplicon Objects
my $mock_sample_1 = Test::MockObject->new();
$mock_sample_1->set_isa( 'Crispr::DB::Sample' );
$mock_sample_1->mock( 'db_id', sub { return 1 } );

my $mock_sample_2 = Test::MockObject->new();
$mock_sample_2->set_isa( 'Crispr::DB::Sample' );
$mock_sample_2->mock( 'db_id', sub { return 2 } );

my $mock_primer_pair_1 = Test::MockObject->new();
$mock_primer_pair_1->set_isa( 'Crispr::PrimerPair' );
$mock_primer_pair_1->mock( 'pair_name', sub { return '5:20340-20590:1' } );

my $mock_primer_pair_2 = Test::MockObject->new();
$mock_primer_pair_2->set_isa( 'Crispr::PrimerPair' );
$mock_primer_pair_2->mock( 'pair_name', sub { return '10:20340-20590:1' } );

my $plate_number = 1;
my ( $barcode_id_1, $well_id_1 ) = ( 1, 'A01' );
my ( $barcode_id_2, $well_id_2 ) = ( 1, 'A02' );

my $sample_amplicon_pairs_1 = Test::MockObject->new();
$sample_amplicon_pairs_1->set_isa( 'Crispr::DB::SampleAmplicon' );
$sample_amplicon_pairs_1->mock( 'sample', sub { return $mock_sample_1; } );
$sample_amplicon_pairs_1->mock( 'amplicons', sub { return [ $mock_primer_pair_1, $mock_primer_pair_2 ]; } );
$sample_amplicon_pairs_1->mock( 'barcode_id', sub { return $barcode_id_1; } );
$sample_amplicon_pairs_1->mock( 'plate_number', sub { return $plate_number; } );
$sample_amplicon_pairs_1->mock( 'well_id', sub { return $well_id_1; } );

my $sample_amplicon_pairs_2 = Test::MockObject->new();
$sample_amplicon_pairs_2->set_isa( 'Crispr::DB::SampleAmplicon' );
$sample_amplicon_pairs_2->mock( 'sample', sub { return $mock_sample_2; } );
$sample_amplicon_pairs_2->mock( 'amplicons', sub { return [ $mock_primer_pair_1, $mock_primer_pair_2 ]; } );
$sample_amplicon_pairs_2->mock( 'barcode_id', sub { return $barcode_id_2; } );
$sample_amplicon_pairs_2->mock( 'plate_number', sub { return $plate_number; } );
$sample_amplicon_pairs_2->mock( 'well_id', sub { return $well_id_2; } );

$analysis = Crispr::DB::Analysis->new(
    db_id => 1,
    plex => $mock_plex,
    info => [ $sample_amplicon_pairs_1, $sample_amplicon_pairs_2 ],
    analysis_started => '2014-09-30',
    analysis_finished => '2014-10-01',
);

# check methods
my @samples = $analysis->samples;
is( scalar @samples, 2, 'check number of samples returned by samples' );
$tests++;
my @primer_pairs = $analysis->amplicons;
is( scalar @primer_pairs, 2, 'check number of amplicons returned by amplicons' );
$tests++;

done_testing( $tests );
