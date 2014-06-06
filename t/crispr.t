#!/usr/bin/env perl
# crispr.t

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;

#plan tests => 15 + 36 + 3 + 4 + 6;
$tests = 0;

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

# check method calls 14 + 23 tests
my @attributes = qw( target_seq PAM five_prime_Gs target_seq_length
species target_genome slice_adaptor targets all_crisprs
annotation_file annotation_tree off_targets_interval_tree debug );

my @methods = qw( 
find_crRNAs_by_region _construct_regex_from_target_seq find_crRNAs_by_target filter_crRNAs_from_target_by_strand filter_crRNAs_from_target_by_score
add_target remove_target add_targets add_crisprs remove_crisprs
_seen_crRNA_id _seen_target_name off_targets_bwa output_fastq_for_off_targets bwa_align
make_bam_and_bed_files filter_and_score_off_targets score_off_targets_from_bed_output calculate_all_pc_coding_scores calculate_pc_coding_score
_build_annotation_tree _build_interval_tree _build_five_prime_Gs );

foreach my $method ( @attributes, @methods ) {
    can_ok( $design_obj, $method );
    $tests++;
}

use Bio::EnsEMBL::Registry;
Bio::EnsEMBL::Registry->load_registry_from_db(
  -host    => 'ensembldb.ensembl.org',
  -user    => 'anonymous',
);
my $slice_adaptor = Bio::EnsEMBL::Registry->get_adaptor( 'zebrafish', 'core', 'slice' );

$design_obj = Crispr->new(
    species => 'zebrafish',
    target_seq => 'NNNNNNNNNNNNNNNNNNNNNGG',
    five_prime_Gs => 0,
    target_genome => '/lustre/scratch110/sanger/rw4/genomes/Dr/Zv9/striped/zv9_toplevel_unmasked.fa',
    slice_adaptor => $slice_adaptor,
    annotation_file => '/lustre/scratch110/sanger/rw4/Crispr/zv9/e72_annotation.gff',
    debug => 0,
);

my $design_obj_no_target_seq = Crispr->new(
    species => 'zebrafish',
    five_prime_Gs => 0,
    target_genome => '/lustre/scratch110/sanger/rw4/genomes/Dr/Zv9/striped/zv9_toplevel_unmasked.fa',
    slice_adaptor => $slice_adaptor,
    annotation_file => '/lustre/scratch110/sanger/rw4/Crispr/zv9/e72_annotation.gff',
    debug => 0,
);

# check attributes
throws_ok { Crispr->new( target_seq => 'NNNNNJNNNNNNNNNNNNNNNGG' ) } qr/Not\sa\svalid\scrRNA\starget\ssequence/, 'Incorrect target seq - non-DNA character';
throws_ok { Crispr->new( five_prime_Gs => 3 ) } qr/Validation\sfailed/, 'Attempt to set five_prime_Gs to 3';
throws_ok { Crispr->new( target_genome => '/lustre/scratch110/sanger/rw4/genomes/Dr/Zv8/striped/zv9_toplevel_unmasked.fa' ) }
    qr/File\sdoes\snot\sexist\sor\sis\sempty/, 'genome file that does not exist';
$tests+=3;

# test methods
# find_crRNAs_by_region - 3 tests
throws_ok { $design_obj_no_target_seq->find_crRNAs_by_region() } qr/A\sregion\smust\sbe\ssupplied\sto\sfind_crRNAs_by_region/,
    'find crRNAs by region - no region';
throws_ok { $design_obj_no_target_seq->find_crRNAs_by_region( '5:46628364-46628423', ) } qr/The\starget_seq\sattribute\smust\sbe\sdefined\sto\ssearch\sfor\scrRNAs/,
    'find crRNAs by region - no target_seq';
throws_ok { $design_obj->find_crRNAs_by_region( '0:46628364-46628423', ) } qr/Couldn't\sunderstand\sregion/,
    'find crRNAs by region - incorrect region format';
throws_ok { $design_obj->find_crRNAs_by_region( '5-46628364-46628423', ) } qr/Couldn't\sunderstand\sregion/,
    'find crRNAs by region - incorrect region format';
ok( $design_obj->find_crRNAs_by_region( '5:46628364-46628423' ), 'find crRNAs by region');
$tests+=5;

# find_crRNAs_by_region - 4 tests
# make mock Target object
my $crRNAs;
$mock_target = Test::MockObject->new();
$mock_target->set_isa( 'Crispr::Target' );
$mock_target->mock( 'name', sub{ return '5:46628364-46628423_b' });
$mock_target->mock( 'region', sub{ return '5:46628364-46628423:1' });
$mock_target->mock( 'crRNAs', sub{ my @args = @_; if( $_[1]){ return $_[1] }else{ return $crRNAs} });
#$mock_target->mock( 'chr', sub{ return 'ATGGATAGACTAGATAGATAG' });
#$mock_target->mock( 'start', sub{ return 'ATGGATAGACTAGATAGATAG' });
#$mock_target->mock( 'end', sub{ return 'AAACCTATCTATCTAGTCTAT' });
#$mock_target->mock( 'strand', sub{ return 'pDR274' });

ok( $design_obj->find_crRNAs_by_target( $mock_target ), 'find crRNAs by target');
throws_ok { $design_obj->find_crRNAs_by_target() }
    qr/A\sCrispr::Target\smust\sbe\ssupplied\sto\sfind_crRNAs_by_target/, 'find crRNAs by target - no target';
throws_ok { $design_obj->find_crRNAs_by_target( 'target' ) }
    qr/A\sCrispr::Target\sobject\sis\srequired\sfor\sfind_crRNAs_by_target/, 'find crRNAs by target - not a Crispr::Target';
throws_ok { $design_obj->find_crRNAs_by_target( $mock_target ) }
    qr/This\starget,\s5:46628364-46628423_b,\shas\sbeen\sseen\sbefore/, 'find crRNAs by target - same target';
$tests+=4;

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

done_testing( $tests );