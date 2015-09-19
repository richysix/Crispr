#!/usr/bin/env perl
# off_target.t
use warnings;
use strict;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use Getopt::Long;

#my $test_data = 't/data/test_targets_plus_crRNAs_plus_coding_scores.txt';
#GetOptions(
#    'test_data=s' => \$test_data,
#);
#
#my $count_output = qx/wc -l $test_data/;
#chomp $count_output;
#$count_output =~ s/\s$test_data//mxs;

plan tests => 1 + 2 + 13 + 8 + 6 + 4 + 1;

use Crispr::OffTargetInfo;

my $off_target = Crispr::OffTargetInfo->new();

# check crRNA and attributes
# 1 test
isa_ok( $off_target, 'Crispr::OffTargetInfo' );

# check attributes and methods 2 + 13 tests
my @attributes = (
    qw{ crRNA_name _off_targets }
);

my @methods = ( qw{ add_off_target all_off_targets _make_and_add_off_target score info
    off_target_counts off_target_hits_by_annotation all_off_target_hits number_exon_hits number_intron_hits
    number_nongenic_hits number_hits _build_off_targets } );

foreach my $attribute ( @attributes ) {
    can_ok( $off_target, $attribute );
}
foreach my $method ( @methods ) {
    can_ok( $off_target, $method );
}

# make mock OffTarget object
my $mock_exon_off_target = Test::MockObject->new();
$mock_exon_off_target->set_isa( 'Crispr::OffTarget' );
$mock_exon_off_target->mock( 'position', sub{ return 'test_chr1:201-123:1' });
$mock_exon_off_target->mock( 'mismatches', sub{ return 2 });
$mock_exon_off_target->mock( 'annotation', sub{ return 'exon' });

# Check methods - 8 tests
is( $off_target->score, 1, 'check off target score 1' );

ok(  $off_target->add_off_target( $mock_exon_off_target ), 'add off_target object' );
throws_ok { $off_target->add_off_target( 'off_target' ) } qr/Argument\smust\sbe\sa\sCrispr::OffTarget\sobject/, 'check throws on Str input';
my $mock_object = Test::MockObject->new();
$mock_object->set_isa( 'Crispr::Target' );
throws_ok { $off_target->add_off_target( $mock_object ) } qr/Argument\smust\sbe\sa\sCrispr::OffTarget\sobject/, "check throws on ref that isn't Crispr::OffTarget input";

isa_ok( $off_target->_off_targets, 'HASH', 'check type of off_targets object' );
is( $off_target->score, 0.9, 'check off target score 2' );

my $mock_intron_off_target = Test::MockObject->new();
$mock_intron_off_target->set_isa( 'Crispr::OffTarget' );
$mock_intron_off_target->mock( 'position', sub{ return 'test_chr3:101-123' });
$mock_intron_off_target->mock( 'mismatches', sub{ return 1 });
$mock_intron_off_target->mock( 'annotation', sub{ return 'intron' });

$off_target->add_off_target( $mock_intron_off_target );
is( $off_target->score, 0.85, 'check off target score 3' );

my $mock_nongenic_off_target = Test::MockObject->new();
$mock_nongenic_off_target->set_isa( 'Crispr::OffTarget' );
$mock_nongenic_off_target->mock( 'position', sub{ return 'test_chr1:1-23' });
$mock_nongenic_off_target->mock( 'mismatches', sub{ return 1 });
$mock_nongenic_off_target->mock( 'annotation', sub{ return 'nongenic' });

$off_target->add_off_target( $mock_nongenic_off_target );
$off_target->add_off_target( $mock_nongenic_off_target );
is( $off_target->score, 0.81, 'check off target score 4' );

# check number attributes - 6 tests
is( $off_target->number_exon_hits, 1, 'check number of exon hits' );
is( $off_target->number_intron_hits, 1, 'check number of intron hits' );
is( $off_target->number_nongenic_hits, 2, 'check number of nongenic hits' );

is( $off_target->off_target_counts, '1|1|2', 'check off target counts' );
my @hits = $off_target->off_target_hits_by_annotation;
my $hits = join('|',
                join('/', @{$hits[0]} ),
                join('/', @{$hits[1]} ),
                join('/', @{$hits[2]} ),
            );
is( $hits, 'test_chr1:201-123:1|test_chr3:101-123|test_chr1:1-23/test_chr1:1-23', 'check off target hits');

like( join("\t", $off_target->info), qr/0.81\t1|1|2\ttest_chr1:201-123:1|test_chr3:101-123|test_chr1:1-23\/test_chr1:1-23/xms, 'check off target info' );

# check all_off_targets - 4 tests
my @off_targets = $off_target->all_off_targets;
is( $off_targets[0]->annotation, 'exon', 'check all_off_targets method 1' );
is( $off_targets[1]->annotation, 'intron', 'check all_off_targets method 2' );
is( $off_targets[2]->annotation, 'nongenic', 'check all_off_targets method 3' );
is( $off_targets[3]->annotation, 'nongenic', 'check all_off_targets method 4' );

# check score = 0 - 1 test
foreach ( 1..10 ){
    $off_target->add_off_target( $mock_exon_off_target );
}
is( $off_target->score, 0, 'check off target score 5' );


