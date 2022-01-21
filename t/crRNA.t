#!/usr/bin/env perl
# crRNA.t
use warnings;
use strict;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;

#plan tests => 1 + 19 + 31 + 4 + 4 + 1 + 4 + 6 + 4 + 2 + 3 + 3 + 5 + 2 + 7 + 4 + 4 + 1 + 5 + 2 + 2 + 2 + 1;
my $tests;

my $species = 'zebrafish';

use Crispr::crRNA;

# TestMethods has methods for making mock objects
use lib 't/lib';
use TestMethods;
my $test_method_obj = TestMethods->new();

# make a mock off-target object
my @exon_hits = ( qw{  } );
my $mock_off_target_object = Test::MockObject->new();
$mock_off_target_object->set_isa( 'Crispr::OffTargetInfo' );
$mock_off_target_object->mock( 'score', sub{ return 0.223 } );
$mock_off_target_object->mock( 'number_exon_hits', sub{ return 1 } );
$mock_off_target_object->mock( 'number_intron_hits', sub{ return 2 } );
$mock_off_target_object->mock( 'number_nongenic_hits', sub{ return 4 } );
$mock_off_target_object->mock( 'info', sub { return ( qw{ 0.88 1/2/0 17:403-425:-1|Zv9_NA1:403-425:-1/18:1000-1022:1| } ) } );

my $mock_target_object = Test::MockObject->new();
$mock_target_object->set_isa( 'Crispr::Target' );
$mock_target_object->mock( 'summary', sub{ return (qw{ ENSE000000035646 ENSDARG00000026374 atpase2 crispr_test }) } );
$mock_target_object->mock( 'info', sub{ return (
    qw{ NULL ENSE000000035646 NULL 5 18078900 18079400 1 zebrafish n ENSDARG00000026374 atpase2 crispr_test 75 NULL }) } );
$mock_target_object->mock( 'assembly', sub{ return undef } );

my $mock_target_object_3 = Test::MockObject->new();
$mock_target_object_3->set_isa( 'Crispr::Target' );
$mock_target_object_3->mock( 'summary', sub{ return (qw{ ENSE000000035646 ENSDARG00000026374 atpase2 crispr_test }) } );
$mock_target_object_3->mock( 'assembly', sub{ return 'Zv9' } );
$mock_target_object_3->mock( 'species', sub{ return 'zebrafish' } );

my $args = {
    add_to_db => 0,
};
my ( $mock_plate, ) = $test_method_obj->create_and_add_plate_object( 'plate', $args, undef );
$args->{mock_plate} = $mock_plate;
my ( $mock_well, ) = $test_method_obj->create_mock_object_and_add_to_db( 'well', $args, undef );

my %coding_scores = (
    ENSDART00000037691 => 0.734,
    ENSDART00000037681 => 0.5,
);

# make a new crRNA - designed should get default value of today's date
my $crRNA = Crispr::crRNA->new(
    chr => '5',
    start => 18078991,
    end => 18079013,
    strand => '1',
    sequence => 'GGCCTTCGGGTTTGACCCCATGG',
    species => 'danio_rerio',
    target => $mock_target_object,
    off_target_hits => $mock_off_target_object,
    coding_scores => \%coding_scores,
);

# new crRNA without a chr
my $crRNA_no_chr = Crispr::crRNA->new(
    start => 50,
    end => 60,
    species => 'Aequorea_victoria',
    sequence => 'GGCCTTCGGGTTTGACCCCATGG',
);

my $crRNA_2 = Crispr::crRNA->new(
    chr => '5',
    start => 18078991,
    end => 18079013,
    strand => '-1',
    sequence => 'GGCCTTCGGGTTTGACCCCATGG',
    target => $mock_target_object_3,
    five_prime_Gs => 1,
);

# check crRNA and attributes
# 1 test
isa_ok( $crRNA, 'Crispr::crRNA' );
$tests++;



# check method calls 19 + 31 tests
my @attributes = ( qw{crRNA_id target name chr start
    end strand sequence species five_prime_Gs
    off_target_hits coding_scores unique_restriction_sites plasmid_backbone primer_pairs
    crRNA_adaptor status status_changed well } );
my @methods = qw( target_id target_name target_summary target_info assembly
    target_gene_name target_gene_id off_target_info off_target_score _parse_strand_input
    _parse_species top_restriction_sites info target_info_plus_crRNA_info target_summary_plus_crRNA_info
    cut_site coding_score_for coding_scores_by_transcript base_composition _build_name
    _build_species _build_five_prime_Gs core_sequence _build_oligo forward_oligo
    reverse_oligo t7_hairpin_oligo t7_fillin_oligo _build_backbone coding_score
    score
);

foreach my $attribute ( @attributes ) {
    can_ok( $crRNA, $attribute );
    $tests++;
}
foreach my $method ( @methods ) {
    can_ok( $crRNA, $method );
    $tests++;
}

# 4 tests - check type constraints for crRNA_id
is( $crRNA->crRNA_id, undef, 'Get id' );

my $tmp_crRNA = Crispr::crRNA->new( crRNA_id => '1' );
is( $tmp_crRNA->crRNA_id, '1', 'Set id' );
throws_ok { Crispr::crRNA->new( crRNA_id => 'string') } qr/Validation failed/ms, 'string id';
throws_ok { Crispr::crRNA->new( crRNA_id => '' ) } qr/Validation failed/ms, 'Empty string id';
$tests += 4;

# 4 tests
is( $crRNA->chr, '5', 'Get chr' );
$tmp_crRNA = Crispr::crRNA->new( chr => '' );
is( $tmp_crRNA->chr, undef, 'Empty string to undef' );
$tmp_crRNA = Crispr::crRNA->new( chr => 'Zv9_NA' );
is( $tmp_crRNA->chr, 'Zv9_NA', 'Set chr Zv9_NA');
$tmp_crRNA = Crispr::crRNA->new( chr => '5' );
is( $tmp_crRNA->chr, '5', 'Set chr 5');
$tests += 4;

# no chr object 1 test
is( $crRNA_no_chr->chr, undef, 'Get undef chr' );
$tests++;

# 4 tests
is( $crRNA->start, 18078991, 'Get start' );
is( $crRNA->end, 18079013, 'Get end' );
throws_ok { Crispr::crRNA->new( start => '' ) } qr/Validation failed/, 'Empty start';
throws_ok { Crispr::crRNA->new( end => '' ) } qr/Validation failed/, 'Empty end';
$tests += 4;

# check strand - 6 tests
is( $crRNA->strand, '1', 'Get strand +');
is( $crRNA_2->strand, '-1', 'Get strand -');
# check default value
is( $tmp_crRNA->strand, '1', 'Check default strand' );
throws_ok { Crispr::crRNA->new( strand => '2' ) } qr/Validation failed/, 'Not a Strand';
# check strand = "+" returns correct value
$tmp_crRNA = Crispr::crRNA->new( strand => "+");
is( $tmp_crRNA->strand, '1', 'check "+" is converted to "1"');
# check strand = "-" returns correct value
$tmp_crRNA = Crispr::crRNA->new( strand => "-");
is( $tmp_crRNA->strand, '-1', 'check "-" is converted to "-1"');
$tests += 6;

# check sequences - 4 test
is( $crRNA->sequence, 'GGCCTTCGGGTTTGACCCCATGG', 'Get seq' );
# test type constraint
throws_ok { Crispr::crRNA->new( sequence => 'GGCCTTCGGGTTTGABCCCATGG' ) } qr/Not a valid DNA sequence/, 'Not a Sequence';
is( $crRNA->core_sequence, 'CCTTCGGGTTTGACCCCA', 'Get seq' );
is( $crRNA_2->core_sequence, 'GCCTTCGGGTTTGACCCCA', 'Get single-G seq' );
$tests += 4;

# check species 4 test
is( $crRNA->species, 'zebrafish', 'Get species 1');
$tmp_crRNA = Crispr::crRNA->new( species => "");
is( $tmp_crRNA->species, undef, 'Get species 2');
$tmp_crRNA = Crispr::crRNA->new();
is( $tmp_crRNA->species, undef, 'Get species 3');
# check 5' Gs with no species
is( $tmp_crRNA->five_prime_Gs, 0, 'Get five_prime_Gs with no species');
$tests += 4;

# check core_sequence - 4 tests
is( $crRNA->core_sequence, 'CCTTCGGGTTTGACCCCA', 'Get core_sequence' );
is( $crRNA_no_chr->core_sequence, 'GGCCTTCGGGTTTGACCCCA', 'Get core_sequence 2' );
is( $crRNA_2->core_sequence, 'GCCTTCGGGTTTGACCCCA', 'Get core_sequence 3' );
throws_ok { $tmp_crRNA->core_sequence }
    qr/Can't produce core sequence without a crRNA sequence/, 'core sequence throws with no sequence';
$tests += 4;

# check five_prime_Gs - 3 tests
is( $crRNA->five_prime_Gs, 2, 'Get five_prime_Gs' );
is( $crRNA_no_chr->five_prime_Gs, 0, 'Get five_prime_Gs 2' );
is( $crRNA_2->five_prime_Gs, 1, 'Get five_prime_Gs 3' );
$tests += 3;

# check oligos 12 tests
is( $crRNA->forward_oligo, 'TAGGCCTTCGGGTTTGACCCCA', 'Get F oligo' );
is( $crRNA->reverse_oligo, 'AAACTGGGGTCAAACCCGAAGG', 'Get R oligo' );

is( $crRNA_2->forward_oligo, 'ATAGGCCTTCGGGTTTGACCCCA', 'Get single-G F oligo' );
is( $crRNA_2->reverse_oligo, 'AAACTGGGGTCAAACCCGAAGGC', 'Get single-G R oligo' );

throws_ok { $tmp_crRNA->forward_oligo }
    qr/Can't produce oligo without a crRNA sequence/, 'forward_oligo throws with no sequence';
throws_ok { $tmp_crRNA->reverse_oligo }
    qr/Can't produce oligo without a crRNA sequence/, 'reverse_oligo throws with no sequence';
throws_ok { $tmp_crRNA->t7_hairpin_oligo }
    qr/Can't produce oligo without a crRNA sequence/, 't7_hairpin_oligo throws with no sequence';
throws_ok { $tmp_crRNA->t7_fillin_oligo }
    qr/Can't produce oligo without a crRNA sequence/, 't7_hairpin_oligo throws with no sequence';

$tmp_crRNA = Crispr::crRNA->new( sequence => 'GGCCTTCGGGTTTGAACCCATGG' );
throws_ok { $tmp_crRNA->forward_oligo }
    qr/Can't produce oligo without a species/, 'forward_oligo throws with no species';
$tmp_crRNA = Crispr::crRNA->new( sequence => 'GGCCTTCGGGTTTGAACCCATGG',
                                species => 'rattus_rattus');
warning_like { $tmp_crRNA->forward_oligo }
    qr/Can't find five-prime nucleotides for species/, 'forward_oligo warns with new species';

# check t7 oligos
is( $crRNA->t7_hairpin_oligo, 'CAAAACAGCATAGCTCTAAAACTGGGGTCAAACCCGAAGGCCTATAGTGAGTCGTATTAACAACATAATACGACTCACTATAGG', 'Get T7 hairpin oligo' );
is( $crRNA->t7_fillin_oligo, 'TAATACGACTCACTATAGGCCTTCGGGTTTGACCCCAGTTTTAGAGCTAGAAATAGCAAG', 'Get T7 fillin oligos' );
$tests += 12;

# check scores - 7 tests
#print join("\t", $crRNA->coding_score, $crRNA->score), "\n";
is( $crRNA->coding_score - 0.617 < 0.001, 1, "check overall coding score");
is( $crRNA->score - 0.4 < 0.001, 1, "check score");
# check score, with coding scores, no off-target
$tmp_crRNA = Crispr::crRNA->new( coding_scores => \%coding_scores );
is( $tmp_crRNA->score - 0.617 < 0.001, 1, "check score, coding scores, no off-target");

my $mock_off_target_object_2 = Test::MockObject->new();
$mock_off_target_object_2->set_isa( 'Crispr::OffTargetInfo' );
$tmp_crRNA = Crispr::crRNA->new( off_target_hits => $mock_off_target_object_2, );
$mock_off_target_object_2->mock( 'score', sub{ return undef } );
is( $tmp_crRNA->score, undef, "check score, off-target with no score, no coding scores");

# check score, with off-target, no coding scores
$mock_off_target_object_2->mock( 'score', sub{ return 0.223 } );
is( $tmp_crRNA->score - 0.223 < 0.001, 1, "check score, off-target, no coding scores");

$mock_off_target_object_2->mock( 'score', sub{ return -0.223 } );
is( $tmp_crRNA->score - 0 < 0.001, 1, "check score, less than 0");
$mock_off_target_object_2->mock( 'score', sub{ return 1.5 } );
is( $tmp_crRNA->score - 0 < 0.001, 1, "check score, more than 1");

$tests += 7;

# test coding_scores - 7 tests
is( $crRNA->coding_score_for( 'ENSDART00000037691' ), 0.734, "check return of coding score for transcript ENSDART00000037691.");
is( $crRNA->coding_score_for( 'ENSDART00000037681' ), 0.5, "check return of coding score for transcript ENSDART00000037681.");
like( join(';', $crRNA->coding_scores_by_transcript), qr/ENSDART00000037681=0.5;ENSDART00000037691=0.734/, "check coding_scores_by_transcript");

$crRNA->coding_score_for( 'ENSDART00000037671', 0.1 );
    #print Dumper( %{$crRNA->coding_scores} );
is( $crRNA->coding_score - 0.445 < 0.001, 1, "check overall coding score after adding a new score");
like( join(';', $crRNA->coding_scores_by_transcript), qr/ENSDART00000037671=0.1;ENSDART00000037681=0.5;ENSDART00000037691=0.734/,
     "check coding_scores_by_transcript after adding a new score");

is( $crRNA_2->coding_score, undef, "check undef coding_score");
isa_ok( $crRNA_2->coding_scores, 'HASH', "check coding_scores empty hashref");
$tests += 7;

# check plasmid_backbone - 5 tests
is( $crRNA->plasmid_backbone, 'pDR274', 'Get plasmid_backbone' );
$tmp_crRNA = Crispr::crRNA->new( start => 51, end => 73, );
warning_like { $tmp_crRNA->plasmid_backbone } qr/Cannot\sdetermine\svector\sbackbone\sfrom\sspecies.\sGuessing\spGERETY-1261/,
    'Warns when no species is defined.';
warning_like { $crRNA_no_chr->plasmid_backbone } qr/Cannot\sdetermine\svector\sbackbone\sfrom\sspecies.\sGuessing\spGERETY-1261/,
    'Warns when species does not exist in hash.';
is( $crRNA_no_chr->plasmid_backbone, 'pGERETY-1261', 'Get plasmid_backbone 2' );
is( $crRNA_2->plasmid_backbone, 'pGERETY-1260', 'Get plasmid_backbone 3' );
$tests += 5;

# check status
is( $crRNA->status, 'DESIGNED', 'status default');
$crRNA->status('PASSED_EMBRYO_SCREENING');
is( $crRNA->status, 'PASSED_EMBRYO_SCREENING', 'new status');
throws_ok { Crispr::crRNA->new( status => 'DESIGND', ) }
    qr/Validation failed/, 'throws on non-allowed status';
$tests += 3;

# well
is( $crRNA->well, undef, 'well default');
ok( $crRNA->well( $mock_well ), 'add mock well object' );
$tests += 2;

# check output of non attribute methods
# check target_info throws with no target - 2 tests
throws_ok{ $crRNA_no_chr->target_info_plus_crRNA_info }
    qr/crRNA\sdoes\snot\shave\san\sassociated\sTarget/, 'target_info called with no target';
throws_ok{ $crRNA_no_chr->target_summary_plus_crRNA_info }
    qr/crRNA\sdoes\snot\shave\san\sassociated\sTarget/, 'target_info called with no target';
$tests += 2;

# check name - 5 tests
is( $crRNA->name, 'crRNA:5:18078991-18079013:1', 'Get name' );
is( $crRNA_no_chr->name, 'crRNA:50-60:1', 'Get name without chr');

# make new target
my $mock_target_object_2 = Test::MockObject->new();
$mock_target_object_2->set_isa( 'Crispr::Target' );
# add target with no gene_name
$crRNA_no_chr->target( $mock_target_object_2 );
is( $crRNA_no_chr->name, 'crRNA:50-60:1', 'Get name with target but no gene name');
# mock subroutines and call name again
$mock_target_object_2->mock( 'info', sub{ return (undef, undef, 'gfp', 'rw4') } );
$mock_target_object_2->mock( 'assembly', sub{ return undef } );
$mock_target_object_2->mock( 'gene_name', sub{ return 'gfp' } );

# make new crRNA without a chr and add target to it
$crRNA_no_chr = Crispr::crRNA->new(
    start => 50,
    end => 60,
    species => 'Aequorea_victoria',
    sequence => 'GGCCTTCGGGTTTGACCCCATGG',
);
$crRNA_no_chr->target( $mock_target_object_2 );
is( $crRNA_no_chr->name, 'crRNA:gfp:50-60:1', 'Get name without chr but with gene_name');
is( $crRNA_2->name, 'crRNA:5:18078991-18079013:-1', 'Get name 2');
$tests += 5;

# check base_composition - 5 tests
# sequence without PAM is GGCCTTCGGGTTTGACCCCA
my $base_composition = $crRNA->base_composition();
is( ref $base_composition, 'HASH', 'base composition - check return value is a hashref');
is( abs($base_composition->{A} - 0.100) < 0.001, 1, 'check A base composition');
is( abs($base_composition->{C} - 0.350) < 0.001, 1, 'check C base composition');
is( abs($base_composition->{G} - 0.300) < 0.001, 1, 'check G base composition');
is( abs($base_composition->{T} - 0.250) < 0.001, 1, 'check T base composition');
$tests += 5;

# crRNA_info - 2 tests
like( join("\t", $crRNA->info ),
    qr/crRNA:5:18078991-18079013:1\t5\t18078991\t18079013\t1\t0.099\tGGCCTTCGGGTTTGACCCCATGG\tTAGGCCTTCGGGTTTGACCCCA\tAAACTGGGGTCAAACCCGAAGG\t0.88\t1\/2\/0\t17:403-425:-1|Zv9_NA1:403-425:-1\/18:1000-1022:1|\t0.445\tENSDART00000037671=0.1;ENSDART00000037681=0.5;ENSDART00000037691=0.734/,
    'check info' );
like( join("\t", $crRNA_2->info ),
    qr/crRNA:5:18078991-18079013:-1\t5\t18078991\t18079013\t-1\tNULL\tGGCCTTCGGGTTTGACCCCATGG\tATAGGCCTTCGGGTTTGACCCCA\tAAACTGGGGTCAAACCCGAAGGC\tNULL\tNULL\tNULL\tNULL\tNULL\t1\tpGERETY-1260/,
    'check info 2');
like( join("\t", $crRNA_2->info(1) ),
    qr/crRNA_name\tcrRNA_chr\tcrRNA_start\tcrRNA_end\tcrRNA_strand\tcrRNA_score\tcrRNA_sequence\tcrRNA_oligo1\tcrRNA_oligo2\tcrRNA_off_target_score\tcrRNA_off_target_counts\tcrRNA_off_target_hits\tcrRNA_coding_score\tcrRNA_coding_scores_by_transcript\tcrRNA_five_prime_Gs\tcrRNA_plasmid_backbone\tcrRNA_GC_content/,
    'check info header');
$tests += 3;

# crRNA target_summary_plus_crRNA_info & target_info_plus_crRNA_info
# 2 tests
like( join("\t", $crRNA->target_summary_plus_crRNA_info ),
    qr/ENSE000000035646\tENSDARG00000026374\tatpase2\tcrispr_test\tcrRNA:5:18078991-18079013:1\t5\t18078991\t18079013\t1\t0.099\tGGCCTTCGGGTTTGACCCCATGG\tTAGGCCTTCGGGTTTGACCCCA\tAAACTGGGGTCAAACCCGAAGG\t0.88\t1\/2\/0\t17:403-425:-1|Zv9_NA1:403-425:-1\/18:1000-1022:1|\t0.445\tENSDART00000037671=0.1;ENSDART00000037681=0.5;ENSDART00000037691=0.734/,
    'check target_summary plus info' );
like( join("\t", $crRNA->target_info_plus_crRNA_info ),
    qr/NULL\tENSE000000035646\tNULL\t5\t18078900\t18079400\t1\tzebrafish\tn\tENSDARG00000026374\tatpase2\tcrispr_test\t75\tNULL\tcrRNA:5:18078991-18079013:1\t5\t18078991\t18079013\t1\t0.099\tGGCCTTCGGGTTTGACCCCATGG\tTAGGCCTTCGGGTTTGACCCCA\tAAACTGGGGTCAAACCCGAAGG\t0.88\t1\/2\/0\t17:403-425:-1|Zv9_NA1:403-425:-1\/18:1000-1022:1|\t0.445\tENSDART00000037671=0.1;ENSDART00000037681=0.5;ENSDART00000037691=0.734/,
    'check target_info plus info' );
$tests += 2;

# check cut-site 2 tests
is( $crRNA->cut_site, 18079007, 'cut_site + strand');
is( $crRNA_2->cut_site, 18078996, 'cut_site + strand');
$tests += 2;

# check getting species from Target - 1 test
is( $crRNA_2->species, 'zebrafish', 'get species from target');
$tests++;

done_testing( $tests );
