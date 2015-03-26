#!/usr/bin/env perl
# sample.t
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
    qw{ db_id injection_pool subplex barcode_id generation
        sample_type alleles species }
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

## crRNAs
#my $mock_crRNA_1 = Test::MockObject->new();
#$mock_crRNA_1->set_isa('Crispr::crRNA');
#$mock_crRNA_1->mock('crRNA_id', sub{ '1' } );
#$mock_crRNA_1->mock('name', sub{ 'crRNA:5:50383-50405:-1' } );
#$mock_crRNA_1->mock('chr', sub{ '5' } );
#$mock_crRNA_1->mock('start', sub{ '50383' } );
#$mock_crRNA_1->mock('end', sub{ '50405' } );
#$mock_crRNA_1->mock('strand', sub{ '-1' } );
#$mock_crRNA_1->mock('cut_site', sub{ '50388' } );
#$mock_crRNA_1->mock('sequence', sub{ 'GGAATAGAGAGATAGAGAGTCGG' } );
#$mock_crRNA_1->mock('forward_oligo', sub{ 'ATGGGGAATAGAGAGATAGAGAGT' } );
#$mock_crRNA_1->mock('reverse_oligo', sub{ 'AAACACTCTCTATCTCTCTATTCC' } );
#$mock_crRNA_1->mock('score', sub{ '0.853' } );
#$mock_crRNA_1->mock('coding_score', sub{ '0.853' } );
#$mock_crRNA_1->mock('off_target_score', sub{ '0.95' } );
#$mock_crRNA_1->mock('target_id', sub{ '1' } );
#$mock_crRNA_1->mock('target', sub{ return $mock_target } );
#$mock_crRNA_1->mock('unique_restriction_sites', sub { return undef } );
#$mock_crRNA_1->mock('coding_scores', sub { return undef } );
#$mock_crRNA_1->mock( 'off_target_hits', sub { return undef } );
#$mock_crRNA_1->mock( 'plasmid_backbone', sub { return 'pDR274' } );
#$mock_crRNA_1->mock( 'primer_pairs', sub { return undef } );
#$mock_crRNA_1->mock( 'info', sub { return ( qw{ crRNA:5:50383-50405:-1 5 50383
#    50405 -1 0.853 GGAATAGAGAGATAGAGAGTCGG ATGGGGAATAGAGAGATAGAGAGT
#    AAACACTCTCTATCTCTCTATTCC NULL NULL NULL NULL NULL NULL NULL 2 pDR274 } ); });
#
#my $mock_crRNA_2 = Test::MockObject->new();
#$mock_crRNA_2->set_isa('Crispr::crRNA');
#$mock_crRNA_2->mock('crRNA_id', sub{ '2' } );
#$mock_crRNA_2->mock('name', sub{ 'crRNA:5:50403-50425:1' } );
#$mock_crRNA_2->mock('chr', sub{ '5' } );
#$mock_crRNA_2->mock('start', sub{ '50403' } );
#$mock_crRNA_2->mock('end', sub{ '50425' } );
#$mock_crRNA_2->mock('strand', sub{ '1' } );
#$mock_crRNA_2->mock('cut_site', sub{ '50419' } );
#$mock_crRNA_2->mock('sequence', sub{ 'GGAATAGAGAGATAGAGAGTCGG' } );
#$mock_crRNA_2->mock('forward_oligo', sub{ 'ATGGGGAATAGAGAGATAGAGAGT' } );
#$mock_crRNA_2->mock('reverse_oligo', sub{ 'AAACACTCTCTATCTCTCTATTCC' } );
#$mock_crRNA_2->mock('score', sub{ '0.853' } );
#$mock_crRNA_2->mock('coding_score', sub{ '0.853' } );
#$mock_crRNA_2->mock('off_target_score', sub{ '0.90' } );
#$mock_crRNA_2->mock('target_id', sub{ '1' } );
#$mock_crRNA_2->mock('target', sub{ return $mock_target } );
#$mock_crRNA_2->mock('unique_restriction_sites', sub { return undef } );
#$mock_crRNA_2->mock('coding_scores', sub { return undef } );
#$mock_crRNA_2->mock( 'off_target_hits', sub { return undef } );
#$mock_crRNA_2->mock( 'plasmid_backbone', sub { return 'pDR274' } );
#$mock_crRNA_2->mock( 'primer_pairs', sub { return undef } );
#$mock_crRNA_2->mock( 'info', sub { return ( qw{ crRNA:5:50403-50425:-1 5 50403
#    50425 1 0.853 GGAATAGAGAGATAGAGAGTCGG ATGGGGAATAGAGAGATAGAGAGT
#    AAACACTCTCTATCTCTCTATTCC NULL NULL NULL NULL NULL NULL NULL 2 pDR274 } ); });


$sample = Crispr::DB::Sample->new(
    db_id => 1,
    injection_pool => $mock_inj_object,
    subplex => $mock_subplex_object,
    barcode_id => 1,
    generation => 'G0',
    sample_type => 'sperm',
    well_id => 'A01',
);

is( $sample->db_id, 1, 'check db_id');
is( $sample->barcode_id, 1, 'check barcode_id');
is( $sample->generation, 'G0', 'check generation');
is( $sample->sample_type, 'sperm', 'check sample_type');
$tests += 4;

# check sample_name
is( $sample->sample_name, '1_A01', 'check sample name' );
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
