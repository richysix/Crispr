#!/usr/bin/env perl
# crispr.t
use warnings;
use strict;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use Crispr::Target;

use File::Spec;
use File::Which;

my $tests = 0;

use lib 't/lib';
use TestMethods;

my $test_method_obj = TestMethods->new();
$test_method_obj->check_for_test_genome( 'mock_genome.fa' );
$test_method_obj->check_for_annotation( 'mock_annotation.gff' );
my $slice_adaptor = $test_method_obj->slice_adaptor;

my $ensembl_version = Bio::EnsEMBL::ApiVersion::software_version();

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

# check method calls 12 + 27 tests
my @attributes = qw( target_seq PAM five_prime_Gs species target_genome
slice_adaptor targets all_crisprs annotation_file annotation_tree
off_targets_interval_tree debug );

my @methods = qw( 
_seen_crRNA_id _seen_target_name find_crRNAs_by_region _construct_regex_from_target_seq find_crRNAs_by_target
filter_crRNAs_from_target_by_strand filter_crRNAs_from_target_by_score add_targets add_target remove_target 
add_crisprs remove_crisprs target_seq_length create_crRNA_from_crRNA_name parse_cr_name
find_off_targets output_fastq_for_off_targets bwa_align filter_and_score_off_targets score_off_targets_from_sam_output
calculate_all_pc_coding_scores calculate_pc_coding_score crRNA_info_header target_info_header
_build_annotation_tree _build_interval_tree _build_five_prime_Gs );

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

my $design_obj_no_slice_adaptor = Crispr->new(
    species => 'zebrafish',
    target_seq => 'NNNNNNNNNNNNNNNNNNNNNGG',
    five_prime_Gs => 0,
    target_genome => 't/data/mock_genome.fa',
    annotation_file => 't/data/mock_annotation.gff',
    debug => 0,
);

# check attributes
throws_ok { Crispr->new( target_seq => 'NNNNNJNNNNNNNNNNNNNNNGG' ) } qr/Not\sa\svalid\scrRNA\starget\ssequence/, 'Incorrect target seq - non-DNA character';
throws_ok { Crispr->new( five_prime_Gs => 3 ) } qr/Validation\sfailed/, 'Attempt to set five_prime_Gs to 3';
throws_ok { Crispr->new( target_genome => 'non_existent_genome_file.fa' ) }
    qr/File\ssupplied\sto\sAttribute\starget_genome\sdoes\snot\sexist\sor\sis\sempty/xms, 'genome file that does not exist';
throws_ok { Crispr->new( annotation_file => 'non_existent_annotation_file.gff' ) }
    qr/File\ssupplied\sto\sAttribute\sannotation_file\sdoes\snot\sexist\sor\sis\sempty/xms, 'annotation file that does not exist';
$tests+=4;

# test methods
# find_crRNAs_by_region - 8 tests
throws_ok { $design_obj_no_target_seq->find_crRNAs_by_region() } qr/A\sregion\smust\sbe\ssupplied\sto\sfind_crRNAs_by_region/,
    'find crRNAs by region - no region';
throws_ok { $design_obj_no_target_seq->find_crRNAs_by_region( '5:46628364-46628423', ) } qr/The\starget_seq\sattribute\smust\sbe\sdefined\sto\ssearch\sfor\scrRNAs/,
    'find crRNAs by region - no target_seq';
throws_ok { $design_obj->find_crRNAs_by_region( '0:46628364-46628423', ) } qr/Couldn't\sunderstand\sregion/,
    'find crRNAs by region - incorrect region format';
throws_ok { $design_obj->find_crRNAs_by_region( '5-46628364-46628423', ) } qr/Couldn't\sunderstand\sregion/,
    'find crRNAs by region - incorrect region format';

# check which version of Ensembl is being used and set regions/number of crisprs accordingly
my ( $region, $num_crisprs, );
if( $ensembl_version <= 79 ){
    $region = '5:17719978-17720144:-1';
    $num_crisprs = 27;
}
elsif ( $ensembl_version <= 91 ){
    $region = '5:15445938-15446104:-1';
    $num_crisprs = 27;
}
else{
    $region = '5:15946155-15946321:-1';
    $num_crisprs = 27;
}

ok( $design_obj->find_crRNAs_by_region( $region ), 'find crRNAs by region');
is( scalar keys %{ $design_obj->all_crisprs }, $num_crisprs, 'check number of crispr sites' );
ok( $design_obj_no_slice_adaptor->find_crRNAs_by_region( 'test_chr1:81-180' ), 'find crRNAs by region - no slice adaptor');
is( scalar keys %{ $design_obj_no_slice_adaptor->all_crisprs }, 16, 'check number of crispr sites - no slice adaptor' );
#warn Dumper( $design_obj_no_slice_adaptor->all_crisprs );
$tests+=8;

# find_crRNAs_by_target - 10 tests
# make mock Target object
my $crRNAs;
my $mock_target = Test::MockObject->new();
$mock_target->set_isa( 'Crispr::Target' );
$mock_target->mock( 'target_name', sub{ return 'ENSDARE00001117797' });
$mock_target->mock( 'crRNAs', sub{ my @args = @_; if( $args[1] ){ $crRNAs = $args[1] }else{ return $crRNAs } } );
$mock_target->mock( 'region', sub{ return undef });

throws_ok { $design_obj->find_crRNAs_by_target() }
    qr/A\sCrispr::Target\smust\sbe\ssupplied\sto\sfind_crRNAs_by_target/, 'find crRNAs by target - no target';
throws_ok { $design_obj->find_crRNAs_by_target( 'target' ) }
    qr/A\sCrispr::Target\sobject\sis\srequired\sfor\sfind_crRNAs_by_target/, 'find crRNAs by target - not a Crispr::Target';
throws_ok { $design_obj->find_crRNAs_by_target( $mock_target ) }
    qr/This\starget\sdoes\snot\shave\san\sassociated\sregion/, 'find crRNAs by target - no region';

$mock_target->mock( 'target_name', sub{ return 'ENSDARE00001117797_2' });
$mock_target->mock( 'region', sub{ return '15445938-15446104' });
throws_ok { $design_obj->find_crRNAs_by_target( $mock_target ) }
    qr/Couldn't\sunderstand\sthe\starget's\sregion/, 'find crRNAs by target - incorrect region format';

# create mock target but use same region
$mock_target->mock( 'region', sub{ return $region });
$mock_target->mock( 'target_name', sub{ return 'ENSDARE00001117797_3' });
throws_ok { $design_obj_no_target_seq->find_crRNAs_by_target( $mock_target ) } qr/The\starget_seq\sattribute\smust\sbe\sdefined\sto\ssearch\sfor\scrRNAs/,
    'find crRNAs by target - no target_seq';

$mock_target->mock( 'target_name', sub{ return 'ENSDARE00001117797_4' });
ok( $design_obj->find_crRNAs_by_target( $mock_target ), 'find crRNAs by target');
is( scalar @{ $design_obj->targets }, 1, 'check number of targets');
is( scalar @{ $mock_target->crRNAs }, $num_crisprs, 'check number of crRNAs');
#print join("\n", map { $_->name } @{ $mock_target->crRNAs } ), "\n";

ok( $design_obj->filter_crRNAs_from_target_by_strand( $mock_target, '1' ), 'filter crRNAs by strand');
is( scalar @{ $mock_target->crRNAs }, 15, 'check crispr left after filtering by + strand' );

throws_ok { $design_obj->find_crRNAs_by_target( $mock_target ) }
    qr/This\starget,.*,\shas\sbeen\sseen\sbefore/, 'find crRNAs by target - same target';
$tests+=11;

my $crRNA_1;
my $crRNA_name = $ensembl_version <= 79 ? 'crRNA:3:5689156-5689178:1' :
    $ensembl_version <= 91 ? 'crRNA:3:5120152-5120174:-1' : 'crRNA:3:5029993-5030015:-1';
ok( $crRNA_1 = $design_obj->create_crRNA_from_crRNA_name( $crRNA_name, 'zebrafish' ), 'create crRNA from crRNA name' );
#print $crRNA_1->sequence();
warning_like { $crRNA_1 = $design_obj_no_slice_adaptor->create_crRNA_from_crRNA_name( 'crRNA:3:5689156-5689178:1', 'zebrafish' ) }
    qr/Couldn't retrieve sequence for crRNA/,
   'create crRNA from crRNA name no slice adaptor';
$tests+=2;

my $off_targets1;
my $coding_scores1 = {};
my $mock_crRNA1 = Test::MockObject->new();
$mock_crRNA1->set_isa( 'Crispr::crRNA' );
$mock_crRNA1->mock( 'name', sub{ return 'crRNA:test_chr1:101-123:1' });
$mock_crRNA1->mock( 'chr', sub{ return 'test_chr1' });
$mock_crRNA1->mock( 'start', sub{ return 101 });
$mock_crRNA1->mock( 'end', sub{ return 123 });
$mock_crRNA1->mock( 'strand', sub{ return '1' });
$mock_crRNA1->mock( 'sequence', sub{ return 'AACTGATCGGGATCGCTATCTGG' });
$mock_crRNA1->mock( 'off_target_hits', sub{ my @args = @_; if( $args[1] ){ $off_targets1 = $args[1] }else{ return $off_targets1 } } );
$mock_crRNA1->mock( 'cut_site', sub{ return 117 });
$mock_crRNA1->mock( 'target', sub{ return $mock_target });

my $off_targets2;
my $coding_scores2 = {};
my $mock_crRNA2 = Test::MockObject->new();
$mock_crRNA2->set_isa( 'Crispr::crRNA' );
$mock_crRNA2->mock( 'name', sub{ return 'crRNA:test_chr2:41-63:1' });
$mock_crRNA2->mock( 'chr', sub{ return 'test_chr2' });
$mock_crRNA2->mock( 'start', sub{ return 41 });
$mock_crRNA2->mock( 'end', sub{ return 63 });
$mock_crRNA2->mock( 'strand', sub{ return '1' });
$mock_crRNA2->mock( 'sequence', sub{ return 'GATCAAAGGCTGCAGTGCAGAGG' });
$mock_crRNA2->mock( 'off_target_hits', sub{ my @args = @_; if( $args[1] ){ $off_targets2 = $args[1] }else{ return $off_targets2 } } );
$mock_crRNA2->mock( 'cut_site', sub{ return 57 });
$mock_crRNA2->mock( 'target', sub{ return $mock_target });

# this array ref is what the mock target crRNAs method returns
$crRNAs = [ $mock_crRNA1, $mock_crRNA2 ];

my $crisprs_hash = {
    'crRNA:test_chr1:101-123:1' => $mock_crRNA1,
    'crRNA:test_chr2:41-63:1' => $mock_crRNA2,
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


SKIP: {
    my $test_num = 3;
    $tests += $test_num;
    # check whether bwa is installed in the current PATH
    my $bwa_path = which( 'bwa' );
    skip "bwa not installed. Skipping off-target finding...", $test_num if !$bwa_path;
    
    ok( $design_obj2->find_off_targets( $design_obj2->all_crisprs,  ), 'off_targets' );
    ## Off Targets for crRNA:test_chr1:101-123:1
    #exon:test_chr1:201-223:1 mismatches:2 annotation:exon
    #intron:test_chr2:101-123:1 mismatches:3 annotation:intron
    #intron:test_chr3:101-123:1 mismatches:1 annotation:intron
    #nongenic:test_chr1:1-23:1 mismatches:1 annotation:nongenic
    #nongenic:test_chr3:201-223:1 mismatches:2 annotation:nongenic
    is( $mock_crRNA1->off_target_hits->score, 0.76, 'check off target score 1');
    is( $mock_crRNA2->off_target_hits->score, 1, 'check off target score 2');
}

# test make_and_add_off_target_from_position
# test args
# OffTargets for crRNA:test_chr2:106-128:1
# intron:test_chr2:206-228:1 mismatches:1 annotation:intron
# exon:test_chr2:406-428:-1 mismatches:1 annotation:exon
my $mock_crRNA3 = Test::MockObject->new();
$mock_crRNA3->set_isa( 'Crispr::crRNA' );
$mock_crRNA3->mock('name', sub { return 'crRNA:test_chr2:106-128:1' } );
$mock_crRNA3->mock('sequence', sub { return 'ATCGCGATCGATATCTGGTTTGG' } );
my $off_target;
$mock_crRNA3->mock( 'off_target_hits', sub{ my @args = @_; if( $args[1] ){ $off_target = $args[1] }else{ return $off_target } });
my $mock_off_target = Test::MockObject->new();
$mock_off_target->set_isa( 'Crispr::OffTargetInfo' );
$mock_off_target->mock( '_make_and_add_off_target', sub{ return 1 });

throws_ok { $design_obj2->make_and_add_off_target_from_position() }
    qr/method: make_and_add_off_target_from_position - One of the arguments was not specified/,
    'make_and_add_off_target_from_position throws on undef args 1';
throws_ok { $design_obj2->make_and_add_off_target_from_position( $mock_crRNA3, ) }
    qr/method: make_and_add_off_target_from_position - One of the arguments was not specified/,
    'make_and_add_off_target_from_position throws on undef args 2';
throws_ok { $design_obj2->make_and_add_off_target_from_position( $mock_crRNA3, '15:192827-192849:1', ) }
    qr/method: make_and_add_off_target_from_position - One of the arguments was not specified/,
    'make_and_add_off_target_from_position throws on undef args 3';
throws_ok { $design_obj2->make_and_add_off_target_from_position( 'mock_crRNA3', '15:192827-192849:1', 'exon') }
    qr/method: make_and_add_off_target_from_position - First argument must be a Crispr::crRNA object/,
    'make_and_add_off_target_from_position throws on args 1 - Str';
my $tmp_mock_crRNA = Test::MockObject->new();
$tmp_mock_crRNA->set_isa( 'Crispr::Target' );
throws_ok { $design_obj2->make_and_add_off_target_from_position( $tmp_mock_crRNA, '15:192827-192849:1', 'exon') }
    qr/method: make_and_add_off_target_from_position - First argument must be a Crispr::crRNA object/,
    'make_and_add_off_target_from_position throws on args 1 - not a Crispr::crRNA';

ok( $design_obj2->make_and_add_off_target_from_position( $mock_crRNA3, 'test_chr2:206-228:1', 'intron'), 'make_and_add_off_target_from_position 1' );
is( $mock_crRNA3->off_target_hits->all_off_target_hits->[0], 'test_chr2:206-228:1', 'check off-target position 1' );

ok( $design_obj2->make_and_add_off_target_from_position( $mock_crRNA3, 'test_chr2:406-428:1', 'exon'), 'make_and_add_off_target_from_position 2' );
is( $mock_crRNA3->off_target_hits->all_off_target_hits->[0], 'test_chr2:406-428:1', 'check off-target position 2' );

throws_ok { $design_obj2->make_and_add_off_target_from_position( $mock_crRNA3, 'test_chr4:406-428:1', 'exon') }
    qr/Couldn't fetch sequence for off-target position to check for mismatches/,
    "make_and_add_off_target_from_position throws - couldn't get sequence";

$tests+=10;

# check if full genome exists and is indexed and test off-target
# skip if genome isn't there or not indexed
SKIP: {
    my $skip = 0;
    my $test_num = 4;
    my $genome_base = File::Spec->catfile('t', 'data', 'Danio_rerio.GRCz11.dna_sm.primary_assembly.fa');
    if( ! -e $genome_base ){
        $skip = 1;
    }
    
    foreach my $suffix ( qw{ amb ann bwt pac sa } ){
        my $index_file = join('.', $genome_base, $suffix );
        if( ! -e $index_file ){
            $skip = 1;
        }
    }
    my $annotation_file = File::Spec->catfile('t', 'data', 'Dr-e100_annotation.gff');
    if( ! -e $annotation_file ){
        $skip = 1;
    }
    
    $tests += $test_num;
    skip "Could not find full genome file or index. Skipping...", $test_num if $skip; 

    my $design_obj = Crispr->new(
        species => 'zebrafish',
        target_seq => 'NNNNNNNNNNNNNNNNNNNNNGG',
        target_genome => $genome_base,
        slice_adaptor => $slice_adaptor,
        annotation_file => 't/data/Dr-e100_annotation.gff',
        debug => 0,
    );
    
    my $target = Crispr::Target->new(
        target_name => 'ENSDARE00000701362',
        chr => '5',
        start => 72289269,
        end => 72289648,
        strand => '1',
        species => 'zebrafish',
        gene_id => 'ENSDARG00000024894',
        gene_name => 'tbx5a',
        requestor => 'crispr_test',
        ensembl_version => 70,
    );
    my $crRNA_1 = $design_obj->create_crRNA_from_crRNA_name( 'crRNA:5:72289297-72289319:-1', 'zebrafish' );
    $crRNA_1->target($target);
    my $crRNA_2 = $design_obj->create_crRNA_from_crRNA_name( 'crRNA:5:72289267-72289289:1', 'zebrafish' );
    $crRNA_2->target($target);
    my $crRNA_3 = $design_obj->create_crRNA_from_crRNA_name( 'crRNA:5:72289319-72289341:-1', 'zebrafish' );
    $crRNA_3->target($target);
    my $crRNA_4 = $design_obj->create_crRNA_from_crRNA_name( 'crRNA:5:72289330-72289352:1', 'zebrafish' );
    $crRNA_4->target($target);
    
    $target->crRNAs( [ $crRNA_1, $crRNA_2, $crRNA_3, $crRNA_4, ] );
    $design_obj->add_target( $target );
    
    ok( $design_obj->add_crisprs( [ $crRNA_1, $crRNA_2, $crRNA_3, $crRNA_4, ], $target->target_name ), 'add_crisprs' );
    ok( $design_obj->remove_crRNAs_from_target( $target, [ $crRNA_4, ] ), 'remove_crisprs_from_target' );
    ok( $design_obj->add_crisprs( [ $crRNA_4, ], $target->target_name ), 'add_crisprs 2' );
    
    ok( $design_obj->find_off_targets( $design_obj->all_crisprs, ), 'check off targets' );
    
    #foreach my $crRNA ( $crRNA_1, $crRNA_2, $crRNA_3, $crRNA_4, ){
    #    my @hits = $crRNA->off_target_hits->off_target_hits;
    #    print join("\t", $crRNA->name,
    #               join(": ", 'exon', @{$hits[0]}, ),
    #               join(": ", 'intron', @{$hits[1]}, ),
    #               join(": ", 'nongenic', @{$hits[2]}, ),
    #            ), "\n";
    #}
};

# SNP FILTERING
SKIP: {
    my $test_num = 7;
    $tests += $test_num;
    
    # check whether tabix is installed in the current PATH
    my $tabix_path = which( 'tabix' );
    # skip tests if not
    skip "tabix not installed. Skipping off-target finding...", $test_num if !$tabix_path;

    # test snps methods - 2 tests
    is( $design_obj->count_var_for_crRNA( $mock_crRNA1, 't/data/test.var.gz' ), 3, 'check count snps for crRNA 1' );
    is( $design_obj->count_var_for_crRNA( $mock_crRNA2, 't/data/test.var.gz' ), 0, 'check count snps for crRNA 2' );
    warning_like { $design_obj->filter_crRNAs_from_target_by_snps_and_indels($mock_target, 't/data/test.var.gz', 1 ) }
        qr/SNP FILTER/, 'check filter crRNAs by SNPs';
    is( scalar @{ $mock_target->crRNAs }, 1, 'check crisprs left after filtering by SNPs' );
    
    # check parameter testing of filter method
    throws_ok{ $design_obj->filter_crRNAs_from_target_by_snps_and_indels() }
        qr/A Crispr::Target object must be supplied/,
        'check filter_crRNAs_from_target_by_snps_and_indels throws when no target supplied';
    throws_ok{ $design_obj->filter_crRNAs_from_target_by_snps_and_indels($mock_target) }
        qr/A variation filename must be supplied/,
        'check filter_crRNAs_from_target_by_snps_and_indels throws when no var file supplied';
    throws_ok{ $design_obj->filter_crRNAs_from_target_by_snps_and_indels($mock_target, 't/data/test.var.g' ) }
        qr/Variation file does not exist or is empty/,
        'check filter_crRNAs_from_target_by_snps_and_indels throws when var file does not exist';

}

# calculate protein coding scores
# change output of mock methods
$mock_crRNA1->mock( 'name', sub{
    return $ensembl_version <= 79 ? 'crRNA:5:17720098-17720120:-1' :
            $ensembl_version <= 91 ? 'crRNA:5:15446058-15446080:-1' : 'crRNA:5:15946275-15946297:-1'} );
$mock_crRNA1->mock( 'chr', sub{ return '5' });
$mock_crRNA1->mock( 'start', sub{ return $ensembl_version <= 79 ? 17720098 : $ensembl_version <= 91 ? 15446058 : 15946275 } );
$mock_crRNA1->mock( 'end', sub{ return $ensembl_version <= 79 ? 17720120 : $ensembl_version <= 91 ? 15446080 : 15946297 } );
$mock_crRNA1->mock( 'cut_site', sub{ return $ensembl_version <= 79 ? 17720103 : $ensembl_version <= 91 ? 15446063 : 15946280 } );
$mock_crRNA1->mock( 'coding_score_for',
    sub{ my @args = @_;
        if( defined $args[2] ){ $coding_scores1->{ $args[1] } = $args[2]; }
        else{ return $coding_scores1->{ $args[1] }; }  } );


$mock_crRNA2->mock( 'name', sub{
    return $ensembl_version <= 79 ? 'crRNA:5:17720150-17720172:-1' :
            $ensembl_version <= 91 ? 'crRNA:5:15446110-15446132:-1' : 'crRNA:5:15946327-15946349:-1'} );
$mock_crRNA2->mock( 'chr', sub{ return '5' });
$mock_crRNA2->mock( 'start', sub{ return $ensembl_version <= 79 ? 17720150 : $ensembl_version <= 91 ? 15446110 : 15946327 } );
$mock_crRNA2->mock( 'end', sub{ return $ensembl_version <= 79 ? 17720172 : $ensembl_version <= 91 ? 15446132 : 15946349 } );
$mock_crRNA2->mock( 'cut_site', sub{ return $ensembl_version <= 79 ? 17720155 : $ensembl_version <= 91 ? 15446115 : 15946332 } );
$mock_crRNA2->mock( 'coding_score_for',
    sub{ my @args = @_;
        if( defined $args[2] ){ $coding_scores2->{ $args[1] } = $args[2]; }
        else{ return $coding_scores2->{ $args[1] }; }  } );

my $gene_adaptor = Bio::EnsEMBL::Registry->get_adaptor( 'zebrafish', 'core', 'gene' );
my $gene = $gene_adaptor->fetch_by_stable_id( 'ENSDARG00000035622' );
my $transcripts = $gene->get_all_Transcripts();

ok( $design_obj2->calculate_all_pc_coding_scores( $mock_crRNA1, $transcripts ), 'pc coding scores 1');
ok( $design_obj2->calculate_all_pc_coding_scores( $mock_crRNA2, $transcripts ), 'pc coding scores 2');

#print $coding_scores1->{ENSDART00000124467}, "\n";
#print abs( $coding_scores1->{ENSDART00000124467} - 0.391 ), "\n";
is( abs( $coding_scores1->{ENSDART00000124467} - 0.391 ) < 0.001, 1, 'check coding scores 1');
is( $coding_scores2->{ENSDART00000124467}, 0, 'check coding scores 2');
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

# test info headers
my @crRNA_info_header = ( qw{ crRNA_name crRNA_chr crRNA_start crRNA_end crRNA_strand
        crRNA_score crRNA_sequence crRNA_oligo1 crRNA_oligo2
        crRNA_off_target_score crRNA_off_target_counts crRNA_off_target_hits
        crRNA_coding_score crRNA_coding_scores_by_transcript crRNA_five_prime_Gs
        crRNA_plasmid_backbone crRNA_GC_content} );
is( $design_obj->crRNA_info_header(), @crRNA_info_header, 'crRNA info header');
my @target_info_header = (qw{ target_id target_name assembly chr start end strand
        species requires_enzyme gene_id gene_name requestor ensembl_version });
is( $design_obj->target_info_header(), @target_info_header, 'target info header');
$tests+=2;

## test output_to_mixed_plate - 6 tests
## make mock crRNA object
#my @list;
#foreach my $name ( 1..48 ){
#    my $mock_crRNA = Test::MockObject->new();
#    $mock_crRNA->set_isa( 'Crispr::crRNA' );
#    $mock_crRNA->mock( 'name', sub{ return $name });
#    $mock_crRNA->mock( 'forward_oligo', sub{ return 'ATGGATAGACTAGATAGATAG' });
#    $mock_crRNA->mock( 'reverse_oligo', sub{ return 'AAACCTATCTATCTAGTCTAT' });
#    $mock_crRNA->mock( 'plasmid_backbone', sub{ return 'pDR274' });
#    push @list, $mock_crRNA;
#}
#
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
