#!/usr/bin/env perl
# sample_amplicon_pairs.t
use warnings;
use strict;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use DateTime;

my $tests;

use Crispr::DB::SampleAmplicon;

# make new object with no attributes
my $sample_amplicon_pairs = Crispr::DB::SampleAmplicon->new();

isa_ok( $sample_amplicon_pairs, 'Crispr::DB::SampleAmplicon');
$tests++;

# check attributes and methods - 5 tests
my @attributes = (
    qw{ sample amplicons barcode_id plate_number well_id }
);

my @methods = ( qw{ } );

foreach my $attribute ( @attributes ) {
    can_ok( $sample_amplicon_pairs, $attribute );
    $tests++;
}
foreach my $method ( @methods ) {
    can_ok( $sample_amplicon_pairs, $method );
    $tests++;
}

my $mock_sample = Test::MockObject->new();
$mock_sample->set_isa( 'Crispr::DB::Sample' );
$mock_sample->mock( 'db_id', sub { return 1 } );

my $mock_primer_pair = Test::MockObject->new();
$mock_primer_pair->set_isa( 'Crispr::PrimerPair' );
$mock_primer_pair->mock( '', sub {} );

my ( $barcode_id, $plate_number, $well_id ) = ( 1, 1, 'A01' );

$sample_amplicon_pairs = Crispr::DB::SampleAmplicon->new(
    analysis_id => 1,
    sample => $mock_sample,
    amplicons => [ $mock_primer_pair ],
    barcode_id => $barcode_id,
    plate_number => $plate_number,
    well_id => $well_id,
);

is( $sample_amplicon_pairs->barcode_id, $barcode_id, 'check barcode_id');
is( $sample_amplicon_pairs->plate_number, $plate_number, 'check plate_number');
is( $sample_amplicon_pairs->well_id, $well_id, 'check well_id');
$tests += 3;

# check type constraint
throws_ok { Crispr::DB::SampleAmplicon->new( sample => $mock_primer_pair ) } qr/Validation\sfailed/, 'check throws if sample is not a Sample object';
$tests++;
throws_ok { Crispr::DB::SampleAmplicon->new( amplicons => $mock_primer_pair ) } qr/Validation\sfailed/, 'check throws if amplicons is not an ArrayRef';
$tests++;
throws_ok { Crispr::DB::SampleAmplicon->new( amplicons => [ $mock_sample ] ) } qr/Validation\sfailed/, 'check throws if amplicon is not an ArrayRef of PrimerPair objects';
$tests++;
throws_ok { Crispr::DB::SampleAmplicon->new( barcode_id => 'One' ) } qr/Validation\sfailed/, 'check throws if barcode_id is a Str';
$tests++;
throws_ok { Crispr::DB::SampleAmplicon->new( plate_number => 'One' ) } qr/Validation\sfailed/, 'check throws if plate_number is a Str';
$tests++;
my $mock_well = Test::MockObject->new();
$mock_well->isa( 'Labware::Well' );
throws_ok { Crispr::DB::SampleAmplicon->new( well_id => $mock_well ) } qr/Validation\sfailed/, 'check throws if well_id is a Labware::Well object';
$tests++;

done_testing( $tests );
