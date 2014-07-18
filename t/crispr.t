#!/usr/bin/env perl
# crispr.t

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;

#plan tests => 15 + 36 + 3 + 4 + 6;
$tests = 0;

use lib 't/lib';
use TestMethods;

my $test_method_obj = TestMethods->new();
$test_method_obj->check_for_test_genome();
$test_method_obj->check_for_annotation();
my $slice_adaptor = $test_method_obj->slice_adaptor;

use Crispr;

# remove files from previous runs
my @files = qw{ CR_000001a.tsv CR_000002a.tsv CR_000003a.tsv CR_000004a.tsv };
foreach ( @files ){
    if( -e ){
        unlink( $_ );
    }
}

# make a crispr object with no attributes
my $design_obj = Crispr->new();

# check method calls 12 + 25 tests
my @attributes = qw( target_seq PAM five_prime_Gs species target_genome
slice_adaptor targets all_crisprs annotation_file annotation_tree
off_targets_interval_tree debug );

my @methods = qw( 
_seen_crRNA_id _seen_target_name find_crRNAs_by_region _construct_regex_from_target_seq find_crRNAs_by_target
filter_crRNAs_from_target_by_strand filter_crRNAs_from_target_by_score add_targets add_target remove_target 
add_crisprs remove_crisprs target_seq_length create_crRNA_from_crRNA_name parse_cr_name
off_targets_bwa output_fastq_for_off_targets bwa_align filter_and_score_off_targets score_off_targets_from_sam_output
calculate_all_pc_coding_scores calculate_pc_coding_score _build_annotation_tree _build_interval_tree _build_five_prime_Gs );

foreach my $method ( @attributes, @methods ) {
    can_ok( $design_obj, $method );
    $tests++;
}

$design_obj = Crispr->new(
    species => 'zebrafish',
    target_seq => 'NNNNNNNNNNNNNNNNNNNNNGG',
    target_genome => 't/data/mock_genome.fa',
    slice_adaptor => $slice_adaptor,
    annotation_file => 't/data/mock_annotation.gff',
    debug => 0,
);

my $design_obj_no_target_seq = Crispr->new(
    species => 'zebrafish',
    five_prime_Gs => 0,
    target_genome => 't/data/mock_genome.fa',
    slice_adaptor => $slice_adaptor,
    annotation_file => 't/data/mock_annotation.gff',
    debug => 0,
);

# check attributes
throws_ok { Crispr->new( target_seq => 'NNNNNJNNNNNNNNNNNNNNNGG' ) } qr/Not\sa\svalid\scrRNA\starget\ssequence/, 'Incorrect target seq - non-DNA character';
throws_ok { Crispr->new( five_prime_Gs => 3 ) } qr/Validation\sfailed/, 'Attempt to set five_prime_Gs to 3';
throws_ok { Crispr->new( target_genome => 'non_existent_genome_file.fa' ) }
    qr/File\sdoes\snot\sexist\sor\sis\sempty/, 'genome file that does not exist';
$tests+=3;

# test methods
# find_crRNAs_by_region - 6 tests
throws_ok { $design_obj_no_target_seq->find_crRNAs_by_region() } qr/A\sregion\smust\sbe\ssupplied\sto\sfind_crRNAs_by_region/,
    'find crRNAs by region - no region';
throws_ok { $design_obj_no_target_seq->find_crRNAs_by_region( '5:46628364-46628423', ) } qr/The\starget_seq\sattribute\smust\sbe\sdefined\sto\ssearch\sfor\scrRNAs/,
    'find crRNAs by region - no target_seq';
throws_ok { $design_obj->find_crRNAs_by_region( '0:46628364-46628423', ) } qr/Couldn't\sunderstand\sregion/,
    'find crRNAs by region - incorrect region format';
throws_ok { $design_obj->find_crRNAs_by_region( '5-46628364-46628423', ) } qr/Couldn't\sunderstand\sregion/,
    'find crRNAs by region - incorrect region format';
ok( $design_obj->find_crRNAs_by_region( '5:46628364-46628423' ), 'find crRNAs by region');
is( scalar keys %{ $design_obj->all_crisprs }, 9, 'check number of crispr sites' );
$tests+=6;

# find_crRNAs_by_target - 10 tests
# make mock Target object
my $crRNAs;
$mock_target = Test::MockObject->new();
$mock_target->set_isa( 'Crispr::Target' );
$mock_target->mock( 'name', sub{ return '5:46628364-46628423_b' });
$mock_target->mock( 'crRNAs', sub{ my @args = @_; if( $args[1] ){ $crRNAs = $args[1] }else{ return $crRNAs } } );
$mock_target->mock( 'region', sub{ return undef });

throws_ok { $design_obj->find_crRNAs_by_target() }
    qr/A\sCrispr::Target\smust\sbe\ssupplied\sto\sfind_crRNAs_by_target/, 'find crRNAs by target - no target';
throws_ok { $design_obj->find_crRNAs_by_target( 'target' ) }
    qr/A\sCrispr::Target\sobject\sis\srequired\sfor\sfind_crRNAs_by_target/, 'find crRNAs by target - not a Crispr::Target';
throws_ok { $design_obj->find_crRNAs_by_target( $mock_target ) }
    qr/This\starget\sdoes\snot\shave\san\sassociated\sregion/, 'find crRNAs by target - no region';

$mock_target->mock( 'name', sub{ return '5:46628364-46628423_c' });
$mock_target->mock( 'region', sub{ return '46628364-46628423' });
throws_ok { $design_obj->find_crRNAs_by_target( $mock_target ) }
    qr/Couldn't\sunderstand\sthe\starget's\sregion/, 'find crRNAs by target - incorrect region format';

$mock_target->mock( 'region', sub{ return '5:46628364-46628423:1' });
$mock_target->mock( 'name', sub{ return '5:46628364-46628423_d' });
throws_ok { $design_obj_no_target_seq->find_crRNAs_by_target( $mock_target ) } qr/The\starget_seq\sattribute\smust\sbe\sdefined\sto\ssearch\sfor\scrRNAs/,
    'find crRNAs by target - no target_seq';

$mock_target->mock( 'name', sub{ return '5:46628364-46628423_e' });
ok( $design_obj->find_crRNAs_by_target( $mock_target ), 'find crRNAs by target');
is( scalar @{ $design_obj->targets }, 1, 'check number of targets');
ok( $design_obj->filter_crRNAs_from_target_by_strand( $mock_target, '1' ), 'filter crRNAs by strand');
is( scalar @{ $mock_target->crRNAs }, 6, 'check crispr left after filtering by + strand' );

throws_ok { $design_obj->find_crRNAs_by_target( $mock_target ) }
    qr/This\starget,\s5:46628364-46628423_e,\shas\sbeen\sseen\sbefore/, 'find crRNAs by target - same target';
$tests+=10;

my $crRNA_1;
ok( $crRNA_1 = $design_obj->create_crRNA_from_crRNA_name( 'crRNA:3:5689156-5689178:1', 'zebrafish' ), 'create crRNA from crRNA name' );
$tests+=1;

my $off_targets1;
my $coding_scores1 = {};
my $mock_crRNA1 = Test::MockObject->new();
$mock_crRNA1->set_isa( 'Crispr::crRNA' );
$mock_crRNA1->mock( 'name', sub{ return 'crRNA:3:5689156-5689178:1' });
$mock_crRNA1->mock( 'chr', sub{ return '3' });
$mock_crRNA1->mock( 'start', sub{ return 5689156 });
$mock_crRNA1->mock( 'end', sub{ return 5689178 });
$mock_crRNA1->mock( 'strand', sub{ return '1' });
$mock_crRNA1->mock( 'sequence', sub{ return 'AACTGATCGGGATCGCTATCTGG' });
$mock_crRNA1->mock( 'off_target_hits', sub{ my @args = @_; if( $args[1] ){ $off_targets1 = $args[1] }else{ return $off_targets1 } } );
$mock_crRNA1->mock( 'cut_site', sub{ return 5689172 });
$mock_crRNA1->mock( 'coding_score_for',
    sub{ my @args = @_;
        if( defined $args[2] ){ $coding_scores1->{ $args[1] } = $args[2]; }
        else{ return $coding_scores1->{ $args[1] }; }  } );

my $off_targets2;
my $coding_scores2 = {};
my $mock_crRNA2 = Test::MockObject->new();
$mock_crRNA2->set_isa( 'Crispr::crRNA' );
$mock_crRNA2->mock( 'name', sub{ return 'crRNA:3:5694768-5694790:1' });
$mock_crRNA2->mock( 'chr', sub{ return '3' });
$mock_crRNA2->mock( 'start', sub{ return 5694768 });
$mock_crRNA2->mock( 'end', sub{ return 5694790 });
$mock_crRNA2->mock( 'strand', sub{ return '1' });
$mock_crRNA2->mock( 'sequence', sub{ return 'GATCAAAGGCTGCAGTGCAGAGG' });
$mock_crRNA2->mock( 'off_target_hits', sub{ my @args = @_; if( $args[1] ){ $off_targets2 = $args[1] }else{ return $off_targets2 } } );
$mock_crRNA2->mock( 'cut_site', sub{ return 5694784 });
$mock_crRNA2->mock( 'coding_score_for',
    sub{ my @args = @_;
        if( defined $args[2] ){ $coding_scores2->{ $args[1] } = $args[2]; }
        else{ return $coding_scores2->{ $args[1] }; }  } );

my $crisprs_hash = {
    'crRNA:3:5689156-5689178:1_gene1' => $mock_crRNA1,
    'crRNA:3:5694768-5694790:1_gene1' => $mock_crRNA2,
};

my $design_obj2 = Crispr->new(
    species => 'zebrafish',
    target_seq => 'NNNNNNNNNNNNNNNNNNNNNGG',
    five_prime_Gs => 0,
    target_genome => 't/data/mock_genome.fa',
    slice_adaptor => $slice_adaptor,
    annotation_file => 't/data/mock_annotation.gff',
    all_crisprs => $crisprs_hash,
    debug => 0,
);

$design_obj2->_testing( 1 );
ok( $design_obj2->off_targets_bwa( $design_obj2->all_crisprs,  ), 'off_targets' );
is( $off_targets1->score, 1, 'check off target score 1');
is( $off_targets2->score, 0.9, 'check off target score 2');
$tests+=3;

# calculate protein coding scores
my $gene_adaptor = Bio::EnsEMBL::Registry->get_adaptor( 'zebrafish', 'core', 'gene' );
my $gene = $gene_adaptor->fetch_by_stable_id( 'ENSDARG00000038399' );
my $transcripts = $gene->get_all_Transcripts();

ok( $design_obj2->calculate_all_pc_coding_scores( $mock_crRNA1, $transcripts ), 'pc coding scores 1');
ok( $design_obj2->calculate_all_pc_coding_scores( $mock_crRNA2, $transcripts ), 'pc coding scores 2');
is( $coding_scores1->{ENSDART00000056037}, 0, 'check coding scores 1');
is( abs( $coding_scores2->{ENSDART00000056037} - 0.56 ) < 0.001, 1, 'check coding scores 2');
$tests+=4;

# check scores
$mock_crRNA1->mock( 'score', sub{ return 0 });
$mock_crRNA1->mock( 'target', sub{ return $mock_target });

$mock_crRNA2->mock( 'score', sub{ return 0.504 });
$mock_crRNA2->mock( 'target', sub{ return $mock_target });

$crRNAs = [ $mock_crRNA1, $mock_crRNA2 ];

ok( $design_obj->filter_crRNAs_from_target_by_score( $mock_target, 1 ), 'filter crRNAs by score');
is( scalar @{ $mock_target->crRNAs }, 1, 'check crisprs left after filtering by score' );
$tests+=2;

# test method remove targets
ok( $design_obj->remove_target( $mock_target ), 'remove target');
is( scalar @{ $design_obj->targets }, 0, 'check number of targets');
$tests+=2;

# test output_to_mixed_plate - 6 tests
# make mock crRNA object
my @list;
foreach my $name ( 1..48 ){
    $mock_crRNA = Test::MockObject->new();
    $mock_crRNA->set_isa( 'Crispr::crRNA' );
    $mock_crRNA->mock( 'name', sub{ return $name });
    $mock_crRNA->mock( 'forward_oligo', sub{ return 'ATGGATAGACTAGATAGATAG' });
    $mock_crRNA->mock( 'reverse_oligo', sub{ return 'AAACCTATCTATCTAGTCTAT' });
    $mock_crRNA->mock( 'plasmid_backbone', sub{ return 'pDR274' });
    push @list, $mock_crRNA;
}

#throws_ok{ $design_obj->output_to_mixed_plate( \@list, 'CR_0000002a', 96, 'column', 'construction_oligos' ) }
#    qr/Plate\sname\sdoesn't\smatch\sthe\scorrect\sformat/, 'throws on incorrect plate name format';
#ok( $design_obj->output_to_mixed_plate( \@list, 'CR_000002a', 96, 'column', 'construction_oligos' ), 'print 48 wells to 96 well plate');
#$tests+=2;
#
## reset list and add 96 wells
#@list = ();
#foreach my $name ( 1..96 ){
#    $mock_crRNA = Test::MockObject->new();
#    $mock_crRNA->set_isa( 'Crispr::crRNA' );
#    $mock_crRNA->mock( 'name', sub{ return $name });
#    $mock_crRNA->mock( 'forward_oligo', sub{ return 'ATGGATAGACTAGATAGATAG' });
#    $mock_crRNA->mock( 'reverse_oligo', sub{ return 'AAACCTATCTATCTAGTCTAT' });
#    $mock_crRNA->mock( 'plasmid_backbone', sub{ return 'pDR274' });
#    push @list, $mock_crRNA;
#}
#ok( $design_obj->output_to_mixed_plate( \@list, 'CR_000001a', 96, 'column', 'construction_oligos' ), 'print to 96 well plate' );
#$tests++;
#
## add another 48 wells
#foreach my $name ( 1..48 ){
#    $mock_crRNA = Test::MockObject->new();
#    $mock_crRNA->set_isa( 'Crispr::crRNA' );
#    $mock_crRNA->mock( 'name', sub{ return $name });
#    $mock_crRNA->mock( 'forward_oligo', sub{ return 'ATGGATAGACTAGATAGATAG' });
#    $mock_crRNA->mock( 'reverse_oligo', sub{ return 'AAACCTATCTATCTAGTCTAT' });
#    $mock_crRNA->mock( 'plasmid_backbone', sub{ return 'pDR274' });
#    push @list, $mock_crRNA;
#}
#
#ok( $design_obj->output_to_mixed_plate( \@list, 'CR_000003a', 96, 'column', 'construction_oligos' ), 'print 144 wells to 96 well plate' );
#ok( (-e 'CR_000003a.tsv'), 'check plate CR_000003a.tsv exists');
#ok( (-e 'CR_000004a.tsv'), 'check plate CR_000004a.tsv exists');
#$tests+=3;
#
## tidy up plate files
#foreach my $file ( qw{ CR_000001a.tsv CR_000002a.tsv CR_000003a.tsv CR_000004a.tsv } ){
#    if( -e $file ){
#        unlink $file;
#    }
#}

# tidy up files
foreach my $file ( qw{ tmp.fq tmp.sai } ){
    if( -e $file ){
        unlink $file;
    }
}

done_testing( $tests );
