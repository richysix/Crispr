#!/usr/bin/env perl
# crRNA.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;

plan tests => 1 + 33 + 4 + 4 + 1 + 4 + 4 + 4 + 1 + 3 + 3 + 5 + 2 + 7 + 4 + 4 + 2 + 2 + 1;

my $species = 'zebrafish';

use Crispr::crRNA;

# make a mock off-target object
my $mock_off_target_object = Test::MockObject->new();
$mock_off_target_object->set_isa( 'Crispr::OffTarget' );
$mock_off_target_object->mock( 'score', sub{ return 0.223 } );
$mock_off_target_object->mock( 'number_seed_exon_hits', sub{ return 1 } );
$mock_off_target_object->mock( 'seed_exon_alignments', sub{ return [ '17:403-425:-1' ] } );
$mock_off_target_object->mock( 'number_seed_intron_hits', sub{ return 2 } );
$mock_off_target_object->mock( 'number_seed_nongenic_hits', sub{ return 4 } );
$mock_off_target_object->mock( 'seed_score', sub{ return 0.528 } );
$mock_off_target_object->mock( 'number_exon_hits', sub{ return 2 } );
$mock_off_target_object->mock( 'exon_alignments', sub{ return [ qw{ 17:403-425:-1 Zv9_NA1:403-425:-1 } ] } );
$mock_off_target_object->mock( 'number_intron_hits', sub{ return 2 } );
$mock_off_target_object->mock( 'number_nongenic_hits', sub{ return 4 } );
$mock_off_target_object->mock( 'exonerate_score', sub{ return 0.422 } );
$mock_off_target_object->mock( 'info', sub { return qw( 0.223 0.528 17:403-425:-1/2/4 0.422 17:403-425:-1,Zv9_NA1:403-425:-1/2/4 ) } );

my $mock_target_object = Test::MockObject->new();
$mock_target_object->set_isa( 'Crispr::Target' );
$mock_target_object->mock( 'info', sub{ return (qw{ ENSE000000035646 ENSDARG00000026374 atpase2 rw4 }) } );
$mock_target_object->mock( 'assembly', sub{ return undef } );

my $mock_target_object_3 = Test::MockObject->new();
$mock_target_object_3->set_isa( 'Crispr::Target' );
$mock_target_object_3->mock( 'info', sub{ return (qw{ ENSE000000035646 ENSDARG00000026374 atpase2 rw4 }) } );
$mock_target_object_3->mock( 'assembly', sub{ return 'Zv9' } );
$mock_target_object_3->mock( 'species', sub{ return 'zebrafish' } );

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

# check method calls 33 tests
my @methods = qw( crRNA_id target chr start end
    strand sequence species five_prime_Gs off_target_hits
    coding_scores unique_restriction_sites plasmid_backbone primer_pairs crRNA_adaptor
    _parse_strand_input _parse_species top_restriction_sites info target_info_plus_crRNA_info
    target_summary_plus_crRNA_info coding_score_for coding_scores_by_transcript name _build_species
    _build_five_prime_Gs core_sequence _build_oligo forward_oligo reverse_oligo
    _build_backbone coding_score score
);

foreach my $method ( @methods ) {
    can_ok( $crRNA, $method );
}

# 4 tests - check type constraints for crRNA_id
is( $crRNA->crRNA_id, undef, 'Get id' );

$tmp_crRNA = Crispr::crRNA->new( crRNA_id => '1' );
is( $tmp_crRNA->crRNA_id, '1', 'Set id' );
throws_ok { Crispr::crRNA->new( crRNA_id => 'string') } qr/Validation failed/ms, 'string id';
throws_ok { Crispr::crRNA->new( crRNA_id => '' ) } qr/Validation failed/ms, 'Empty string id';

# 4 tests
is( $crRNA->chr, '5', 'Get chr' );
$tmp_crRNA = Crispr::crRNA->new( chr => '' );
is( $tmp_crRNA->chr, undef, 'Empty string to undef' );
$tmp_crRNA = Crispr::crRNA->new( chr => 'Zv9_NA' );
is( $tmp_crRNA->chr, 'Zv9_NA', 'Set chr Zv9_NA');
$tmp_crRNA = Crispr::crRNA->new( chr => '5' );
is( $tmp_crRNA->chr, '5', 'Set chr 5');

# no chr object 1 test
is( $crRNA_no_chr->chr, undef, 'Get undef chr' );

# 4 tests
is( $crRNA->start, 18078991, 'Get start' );
is( $crRNA->end, 18079013, 'Get end' );
throws_ok { Crispr::crRNA->new( start => '' ) } qr/Validation failed/, 'Empty start';
throws_ok { Crispr::crRNA->new( end => '' ) } qr/Validation failed/, 'Empty end';

# check strand - 4 tests
is( $crRNA->strand, '1', 'Get strand +');
is( $crRNA_2->strand, '-1', 'Get strand +');
# check default value
is( $tmp_crRNA->strand, '1', 'Check default strand' );
throws_ok { Crispr::crRNA->new( strand => '2' ) } qr/Validation failed/, 'Not a Strand';

# check sequences - 4 test
is( $crRNA->sequence, 'GGCCTTCGGGTTTGACCCCATGG', 'Get seq' );
# test type constraint
throws_ok { Crispr::crRNA->new( sequence => 'GGCCTTCGGGTTTGABCCCATGG' ) } qr/Not a valid DNA sequence/, 'Not a Sequence';
is( $crRNA->core_sequence, 'CCTTCGGGTTTGACCCCA', 'Get seq' );
is( $crRNA_2->core_sequence, 'GCCTTCGGGTTTGACCCCA', 'Get single-G seq' );

# check species 1 test
is( $crRNA->species, 'zebrafish', 'Get species');

# check core_sequence - 3 tests
is( $crRNA->core_sequence, 'CCTTCGGGTTTGACCCCA', 'Get core_sequence' );
is( $crRNA_no_chr->core_sequence, 'GGCCTTCGGGTTTGACCCCA', 'Get core_sequence 2' );
is( $crRNA_2->core_sequence, 'GCCTTCGGGTTTGACCCCA', 'Get core_sequence 3' );

# check five_prime_Gs - 3 tests
is( $crRNA->five_prime_Gs, 2, 'Get five_prime_Gs' );
is( $crRNA_no_chr->five_prime_Gs, 0, 'Get five_prime_Gs 2' );
is( $crRNA_2->five_prime_Gs, 1, 'Get five_prime_Gs 3' );

# check oligos 5 tests
is( $crRNA->forward_oligo, 'TAGGCCTTCGGGTTTGACCCCA', 'Get F oligo' );
is( $crRNA->reverse_oligo, 'AAACTGGGGTCAAACCCGAAGG', 'Get R oligo' );

is( $crRNA_2->forward_oligo, 'ATAGGCCTTCGGGTTTGACCCCA', 'Get single-G F oligo' );
is( $crRNA_2->reverse_oligo, 'AAACTGGGGTCAAACCCGAAGGC', 'Get single-G R oligo' );

# check t7_hairpin oligos
is( $crRNA->t7_hairpin_oligo, 'CAAAACAGCATAGCTCTAAAACTGGGGTCAAACCCGAAGGCCTATAGTGAGTCGTATTAACAACATAATACGACTCACTATAGG', 'Get T7 hairpin oligo' );

# check scores - 2 tests
#print join("\t", $crRNA->coding_score, $crRNA->score), "\n";
is( $crRNA->coding_score - 0.617 < 0.001, 1, "check overall coding score");
is( $crRNA->score - 0.4 < 0.001, 1, "check score");

# test coding_scores - 7 tests
is( $crRNA->coding_score_for( 'ENSDART00000037691' ), 0.734, "check return of coding score for transcript ENSDART00000037691.");
is( $crRNA->coding_score_for( 'ENSDART00000037681' ), 0.5, "check return of coding score for transcript ENSDART00000037681.");
like( join(';', $crRNA->coding_scores_by_transcript), qr/ENSDART00000037691=0.734;ENSDART00000037681=0.5/, "check coding_scores_by_transcript");

$crRNA->coding_score_for( 'ENSDART00000037671', 0.1 );
    #print Dumper( %{$crRNA->coding_scores} );
is( $crRNA->coding_score - 0.445 < 0.001, 1, "check overall coding score after adding a new score");
like( join(';', $crRNA->coding_scores_by_transcript), qr/ENSDART00000037691=0.734;ENSDART00000037681=0.5;ENSDART00000037671=0.1/,
     "check coding_scores_by_transcript after adding a new score");

is( $crRNA_2->coding_score, undef, "check undef coding_scores");
is( $crRNA_2->coding_scores, undef, "check undef coding_scores hashref");

# check plasmid_backbone - 4 tests
is( $crRNA->plasmid_backbone, 'pDR274', 'Get plasmid_backbone' );
warning_like { $crRNA_no_chr->plasmid_backbone } qr/Cannot\sdetermine\svector\sbackbone\sfrom\sspecies.\sGuessing\spGERETY-1261/,
    'Warns when no species is defined.';
is( $crRNA_no_chr->plasmid_backbone, 'pGERETY-1261', 'Get plasmid_backbone 2' );
is( $crRNA_2->plasmid_backbone, 'pGERETY-1260', 'Get plasmid_backbone 3' );

# check output of non attribute methods
# check name - 4 tests
is( $crRNA->name, 'crRNA:5:18078991-18079013:1', 'Get name' );
is( $crRNA_no_chr->name, 'crRNA:50-60:1', 'Get name without chr');

my $mock_target_object_2 = Test::MockObject->new();
$mock_target_object_2->set_isa( 'Crispr::Target' );
$mock_target_object_2->mock( 'info', sub{ return (undef, undef, 'gfp', 'rw4') } );
$mock_target_object_2->mock( 'assembly', sub{ return undef } );
$mock_target_object_2->mock( 'gene_name', sub{ return 'gfp' } );
$crRNA_no_chr->target( $mock_target_object_2 );

is( $crRNA_no_chr->name, 'crRNA:gfp:50-60:1', 'Get name without chr but with gene_name');
is( $crRNA_2->name, 'crRNA:5:18078991-18079013:-1', 'Get name 2');

# crRNA_info - 2 tests
like( join("\t", $crRNA->info ),
    qr/crRNA:5:18078991-18079013:1\t5\t18078991\t18079013\t1\t0.099\tGGCCTTCGGGTTTGACCCCATGG\tTAGGCCTTCGGGTTTGACCCCA\tAAACTGGGGTCAAACCCGAAGG\t0.223\t0.528\t17:403-425:-1\/2\/4\t0.422\t17:403-425:-1,Zv9_NA1:403-425:-1\/2\/4\t0.445\tENSDART00000037691=0.734;ENSDART00000037681=0.5/,
    'check info' );
like( join("\t", $crRNA_2->info ),
    qr/crRNA:5:18078991-18079013:-1\t5\t18078991\t18079013\t-1\tNULL\tGGCCTTCGGGTTTGACCCCATGG\tATAGGCCTTCGGGTTTGACCCCA\tAAACTGGGGTCAAACCCGAAGGC\tNULL\tNULL\tNULL\tNULL\tNULL\tNULL\tNULL/,
    'check info 2');

# check cut-site 2 tests
is( $crRNA->cut_site, 18079007, 'cut_site + strand');
is( $crRNA_2->cut_site, 18078996, 'cut_site + strand');

# check getting species from Target - 1 test
is( $crRNA_2->species, 'zebrafish', 'get species from target');

