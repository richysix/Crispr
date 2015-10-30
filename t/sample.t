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

use Crispr::DB::Sample;

# make new object with no attributes
my $sample = Crispr::DB::Sample->new();

isa_ok( $sample, 'Crispr::DB::Sample');
$tests++;

# check attributes and methods - 9 tests
my @attributes = (
    qw{ db_id injection_pool generation
        sample_type sample_number alleles species }
);

my @methods = ( qw{ sample_name } );

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
my $inj_db_id = 1;
my $pool_name = '170';
my $cas9_conc = 200;
my $guideRNA_conc = 20;
my $guideRNA_type = 'sgRNA';
my $date_obj = DateTime->now();

my $mock_inj_object = Test::MockObject->new();
$mock_inj_object->set_isa( 'Crispr::DB::InjectionPool' );
$mock_inj_object->mock( 'db_id', sub{ return $inj_db_id } );
$mock_inj_object->mock( 'pool_name', sub{ return $pool_name } );
$mock_inj_object->mock( 'cas9_conc', sub{ return $cas9_conc } );
$mock_inj_object->mock( 'guideRNA_conc', sub{ return $guideRNA_conc } );
$mock_inj_object->mock( 'guideRNA_type', sub{ return $guideRNA_type } );
$mock_inj_object->mock( 'date', sub{ return $date_obj->ymd } );

my $mock_subplex_object = Test::MockObject->new();
$mock_subplex_object->set_isa( 'Crispr::DB::Subplex' );
$mock_subplex_object->mock( 'plex_name', sub{ return '8' } );
$mock_subplex_object->mock( 'db_id', sub{ return 1 } );

my $mock_well_object = Test::MockObject->new();
$mock_well_object->set_isa( 'Labware::Well' );
$mock_well_object->mock( 'position', sub { return 'A01' } );

$sample = Crispr::DB::Sample->new(
    db_id => 1,
    injection_pool => $mock_inj_object,
    generation => 'G0',
    sample_type => 'sperm',
    sample_number => 1,
    species => 'zebrafish',
    well => $mock_well_object,
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
is( $sample->sample_name, '170_A01', 'check sample name' );
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
    injection_pool => $mock_inj_object,
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
    injection_pool => $mock_inj_object,
    generation => 'G0',
    sample_type => 'sperm',
    species => 'zebrafish',
    well => undef,
    cryo_box => undef
);
is( $tmp_sample->sample_name, undef, 'check sample name: no well or sample number' );
$tests++;

# check alleles attribute
# make mock allele object
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

my $mock_allele2_object = Test::MockObject->new();
$mock_allele2_object->set_isa( 'Crispr::Allele' );
$mock_allele2_object->mock( 'db_id', sub{ return $allele_db_id } );
$mock_allele2_object->mock( 'chr', sub{ return $chr } );
$mock_allele2_object->mock( 'pos', sub{ return $pos } );
$mock_allele2_object->mock( 'ref_allele', sub{ return $ref_allele } );
$mock_allele2_object->mock( 'alt_allele', sub{ return $alt_allele } );

ok( $sample->alleles( [ $mock_allele_object, $mock_allele2_object ] ), 'set alleles attribute');
$tests++;

done_testing( $tests );
