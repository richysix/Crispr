#!/usr/bin/env perl
# injection_pool.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;

my $tests;

use Crispr::DB::InjectionPool;

# make new object with no attributes
my $injection_pool = Crispr::DB::InjectionPool->new();

isa_ok( $injection_pool, 'Crispr::DB::InjectionPool');
$tests++;

# check attributes and methods - 12 tests
my @attributes = ( qw{ db_id pool_name cas9_prep cas9_conc guideRNA_conc
    guideRNA_type date line_injected line_raised sorted_by guideRNAs }
);

my @methods = ( qw{ _parse_date _build_date } );

foreach my $attribute ( @attributes ) {
    can_ok( $injection_pool, $attribute );
    $tests++;
}
foreach my $method ( @methods ) {
    can_ok( $injection_pool, $method );
    $tests++;
}

# check default attributes
my $db_id = undef;
my $guide_type = 'sgRNA';
my $todays_date_obj = DateTime->now();
is( $injection_pool->db_id, $db_id, 'check db_id default');
$tests++;
is( $injection_pool->guideRNA_type, $guide_type, 'check guideRNA_type default');
$tests++;
is( $injection_pool->date, $todays_date_obj->ymd, 'check date default');
$tests++;

# make mock Cas9 and Cas9Prep object
my $type = 'cas9_dnls_native';
my $species = 's_pyogenes';
my $target_seq = 'NNNNNNNNNNNNNNNNNN';
my $pam = 'NGG';
my $crispr_target_seq = $target_seq . $pam;
my $mock_cas9_object = Test::MockObject->new();
$mock_cas9_object->set_isa( 'Crispr::Cas9' );
$mock_cas9_object->mock( 'type', sub{ return $type } );
$mock_cas9_object->mock( 'species', sub{ return $species } );
$mock_cas9_object->mock( 'target_seq', sub{ return $target_seq } );
$mock_cas9_object->mock( 'PAM', sub{ return $pam } );
$mock_cas9_object->mock( 'crispr_target_seq', sub{ return $crispr_target_seq } );
$mock_cas9_object->mock( 'info', sub{ return ( $type, $species, $crispr_target_seq ) } );

my $prep_type = 'rna';
my $made_by = 'crispr_test';

my $mock_cas9_prep_object = Test::MockObject->new();
$mock_cas9_prep_object->set_isa( 'Crispr::DB::Cas9Prep' );
$mock_cas9_prep_object->mock( 'cas9', sub{ return $mock_cas9_object } );
$mock_cas9_prep_object->mock( 'prep_type', sub{ return $prep_type } );
$mock_cas9_prep_object->mock( 'made_by', sub{ return $made_by } );
$mock_cas9_prep_object->mock( 'date', sub{ return $todays_date_obj->ymd } );

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


$injection_pool = Crispr::DB::InjectionPool->new(
    pool_name => '170',
    cas9_prep => $mock_cas9_prep_object,
    cas9_conc => 200,
    guideRNA_conc => 20,
    guideRNA_type => 'tracrRNA',
    date => '2014-05-24',
    line_injected => 'line1',
    line_raised => 'line2',
    sorted_by => 'crispr_test',
    guideRNAs => [ $mock_crRNA_1, $mock_crRNA_2 ],
);

is( $injection_pool->pool_name, '170', 'check pool_name');
is( $injection_pool->cas9_conc, 200, 'check cas9_conc');
is( $injection_pool->guideRNA_conc, 20, 'check guideRNA_conc');
is( $injection_pool->guideRNA_type, 'tracrRNA', 'check guideRNA_type');
is( $injection_pool->date, '2014-05-24', 'check date');
is( $injection_pool->line_injected, 'line1', 'check line_injected');
is( $injection_pool->line_raised, 'line2', 'check line_raised');
is( $injection_pool->sorted_by, 'crispr_test', 'check sorted_by');
$tests += 8;

# check it throws with non date input
throws_ok { Crispr::DB::InjectionPool->new( date => '14-05-24' ) } qr/The\sdate\ssupplied\sis\snot\sa\svalid\sformat/, 'non valid date format';
$tests++;

done_testing( $tests );