#!/usr/bin/env perl
# crispr_pair.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;

my $tests;

use Crispr::CrisprPair;

# make mock objects
# TARGET
my $mock_target = Test::MockObject->new();
$mock_target->set_isa('Crispr::Target');
$mock_target->mock('name', sub{ 'name' } );
$mock_target->mock('assembly', sub{ 'Zv9' } );
$mock_target->mock('chr', sub{ '5' } );
$mock_target->mock('start', sub{ '50000' } );
$mock_target->mock('end', sub{ '50500' } );
$mock_target->mock('strand', sub{ '1' } );
$mock_target->mock('species', sub{ 'zebrafish' } );
$mock_target->mock('requires_enzyme', sub{ 'n' } );
$mock_target->mock('gene_id', sub{ 'ENSDARG0100101' } );
$mock_target->mock('gene_name', sub{ 'gene_name' } );
$mock_target->mock('requestor', sub{ 'crispr_test' } );
$mock_target->mock('ensembl_version', sub{ '71' } );
$mock_target->mock('designed', sub{ '2013-08-09' } );
$mock_target->mock('target_id', sub{ '1' } );
$mock_target->mock('info', sub{ return ( qw{ 1 name Zv9 5 50000 50500 1
    zebrafish n  ENSDARG0100101 gene_name crispr_test 71 2013-08-09 } ) } );

# crRNAs
my $mock_crRNA_1 = Test::MockObject->new();
$mock_crRNA_1->set_isa('Crispr::crRNA');
$mock_crRNA_1->mock('crRNA_id', sub{ '1' } );
$mock_crRNA_1->mock('name', sub{ 'crRNA:5:50383-50405:-1' } );
$mock_crRNA_1->mock('chr', sub{ '5' } );
$mock_crRNA_1->mock('start', sub{ '50383' } );
$mock_crRNA_1->mock('end', sub{ '50405' } );
$mock_crRNA_1->mock('strand', sub{ '-1' } );
$mock_crRNA_1->mock('cut_site', sub{ '50388' } );
$mock_crRNA_1->mock('sequence', sub{ 'GGAATAGAGAGATAGAGAGTCGG' } );
$mock_crRNA_1->mock('forward_oligo', sub{ 'ATGGGGAATAGAGAGATAGAGAGT' } );
$mock_crRNA_1->mock('reverse_oligo', sub{ 'AAACACTCTCTATCTCTCTATTCC' } );
$mock_crRNA_1->mock('score', sub{ '0.853' } );
$mock_crRNA_1->mock('coding_score', sub{ '0.853' } );
$mock_crRNA_1->mock('off_target_score', sub{ '0.95' } );
$mock_crRNA_1->mock('target_id', sub{ '1' } );
$mock_crRNA_1->mock('target', sub{ return $mock_target } );
$mock_crRNA_1->mock('unique_restriction_sites', sub { return undef } );
$mock_crRNA_1->mock('coding_scores', sub { return undef } );
$mock_crRNA_1->mock( 'off_target_hits', sub { return undef } );
$mock_crRNA_1->mock( 'plasmid_backbone', sub { return 'pDR274' } );
$mock_crRNA_1->mock( 'primer_pairs', sub { return undef } );
$mock_crRNA_1->mock( 'info', sub { return ( qw{ crRNA:5:50383-50405:-1 5 50383
    50405 -1 0.853 GGAATAGAGAGATAGAGAGTCGG ATGGGGAATAGAGAGATAGAGAGT
    AAACACTCTCTATCTCTCTATTCC NULL NULL NULL NULL NULL NULL NULL 2 pDR274 } ); });

my $mock_crRNA_2 = Test::MockObject->new();
$mock_crRNA_2->set_isa('Crispr::crRNA');
$mock_crRNA_2->mock('crRNA_id', sub{ '2' } );
$mock_crRNA_2->mock('name', sub{ 'crRNA:5:50403-50425:1' } );
$mock_crRNA_2->mock('chr', sub{ '5' } );
$mock_crRNA_2->mock('start', sub{ '50403' } );
$mock_crRNA_2->mock('end', sub{ '50425' } );
$mock_crRNA_2->mock('strand', sub{ '1' } );
$mock_crRNA_2->mock('cut_site', sub{ '50419' } );
$mock_crRNA_2->mock('sequence', sub{ 'GGAATAGAGAGATAGAGAGTCGG' } );
$mock_crRNA_2->mock('forward_oligo', sub{ 'ATGGGGAATAGAGAGATAGAGAGT' } );
$mock_crRNA_2->mock('reverse_oligo', sub{ 'AAACACTCTCTATCTCTCTATTCC' } );
$mock_crRNA_2->mock('score', sub{ '0.853' } );
$mock_crRNA_2->mock('coding_score', sub{ '0.853' } );
$mock_crRNA_2->mock('off_target_score', sub{ '0.90' } );
$mock_crRNA_2->mock('target_id', sub{ '1' } );
$mock_crRNA_2->mock('target', sub{ return $mock_target } );
$mock_crRNA_2->mock('unique_restriction_sites', sub { return undef } );
$mock_crRNA_2->mock('coding_scores', sub { return undef } );
$mock_crRNA_2->mock( 'off_target_hits', sub { return undef } );
$mock_crRNA_2->mock( 'plasmid_backbone', sub { return 'pDR274' } );
$mock_crRNA_2->mock( 'primer_pairs', sub { return undef } );
$mock_crRNA_2->mock( 'info', sub { return ( qw{ crRNA:5:50403-50425:-1 5 50403
    50425 1 0.853 GGAATAGAGAGATAGAGAGTCGG ATGGGGAATAGAGAGATAGAGAGT
    AAACACTCTCTATCTCTCTATTCC NULL NULL NULL NULL NULL NULL NULL 2 pDR274 } ); });


my $crispr_pair = Crispr::CrisprPair->new(
    pair_id => undef,
    target_name => 'test_target',
    target_1 => $mock_target,
    target_2 => $mock_target,
    crRNA_1 => $mock_crRNA_1,
    crRNA_2 => $mock_crRNA_2,
    paired_off_targets => 0,
    overhang_top => 'GATAGATAGCGATAGACAG',
    overhang_bottom => 'GACTACGATGAAGATACGA',
);

isa_ok( $crispr_pair, 'Crispr::CrisprPair');
$tests++;

# check method calls 17 tests
my @methods = qw( 
    pair_id target_name target_1 target_2 crRNA_1
    crRNA_2 paired_off_targets overhang_top overhang_bottom crRNAs
    pair_name name combined_single_off_target_score combined_distance_from_targets deletion_size
    pair_info increment_paired_off_targets
);

foreach my $method ( @methods ) {
    can_ok( $crispr_pair, $method );
    $tests++;
}


isa_ok( $crispr_pair->crRNAs, 'ARRAY', 'check crRNAs method returns an ArrayRef' );
$tests++;

is( $crispr_pair->pair_name, 'crRNA:5:50383-50405:-1_crRNA:5:50403-50425:1', 'pair name method');
$tests++;
is( $crispr_pair->name, 'crRNA:5:50383-50405:-1_crRNA:5:50403-50425:1', 'name method' );
$tests++;
is( $crispr_pair->combined_single_off_target_score, 0.855, 'combined_single_off_target_score');
$tests++;
is( $crispr_pair->deletion_size, 31, 'deletion_size');
$tests++;
my @test_info = ( qw{ test_target crRNA:5:50383-50405:-1_crRNA:5:50403-50425:1 0 0.855 31
1 name Zv9 5 50000 50500 1 zebrafish n ENSDARG0100101
gene_name crispr_test 71 2013-08-09
crRNA:5:50383-50405:-1 5 50383 50405 -1 0.853 GGAATAGAGAGATAGAGAGTCGG
ATGGGGAATAGAGAGATAGAGAGT AAACACTCTCTATCTCTCTATTCC NULL NULL NULL NULL NULL NULL NULL 2 pDR274 
1 name Zv9 5 50000 50500 1 zebrafish n ENSDARG0100101
gene_name crispr_test 71 2013-08-09
crRNA:5:50403-50425:-1 5 50403 50425 1 0.853
GGAATAGAGAGATAGAGAGTCGG ATGGGGAATAGAGAGATAGAGAGT AAACACTCTCTATCTCTCTATTCC NULL
NULL NULL NULL NULL NULL NULL 2 pDR274 } );
my $reg_str = join("\\s", @test_info);
like( join("\t", $crispr_pair->pair_info), qr/$reg_str/, 'pair_info' );
$tests++;

is( $crispr_pair->increment_paired_off_targets(), 1, 'increment_paired_off_targets');
is( $crispr_pair->increment_paired_off_targets(2), 3, 'increment_paired_off_targets');
$tests+=2;

done_testing( $tests );