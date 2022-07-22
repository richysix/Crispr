#!/usr/bin/env perl
# scripts.t
use warnings;
use strict;
use File::Which;
use Test::More;

BEGIN {
    if( !$ENV{RELEASE_TESTING} ) {
        require Test::More;
        Test::More::plan(
            skip_all => 'these tests are for release candidate testing' );
    }
    my $bwa_path = which( 'bwa' );
    if( !$bwa_path ){
        Test::More::plan(
            skip_all => 'Could not run tests. bwa is not installed in current path' );
    }
}

use autodie;
use English qw( -no_match_vars );
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use File::Spec;

plan tests => 1 + 3 + 3 + 2;

#get current date
use DateTime;
my $date_obj = DateTime->now();
my $todays_date = $date_obj->ymd;


open my $tmp_fh, '>', 'crispr.tmp' or die "Couldn't open temp file crispr.tmp to write to!\n";
print $tmp_fh join("\t", qw{ crRNA:test_chr1:101-123:1 crispr_test test_target_1 ENSTESTG00000001 gene1 }, ), "\n";
print $tmp_fh join("\t", qw{ crRNA:test_chr2:41-63:1 crispr_test test_target_2 ENSTESTG00000002 gene2}, ), "\n";
close $tmp_fh;

my $annotation_file = File::Spec->catfile( 't', 'data', 'mock_annotation.gff' );
my $genome_file = File::Spec->catfile( 't', 'data', 'mock_genome.fa' );

my $score_crispr_cmd = join(q{ }, 'perl -I lib scripts/score_crisprs_from_id.pl',
    '--singles', '--species zebrafish', '--num_five_prime_Gs 0',
    '--file_base tmp', '--target_genome', $genome_file,
    "--annotation_file", $annotation_file, 'crispr.tmp',
    '2>', 'tmp.err', );

# run score_crisprs_from_id.pl script - 1 test
system( $score_crispr_cmd );
ok( $? >> 8 == 0, 'run score_crisprs_from_id.pl mock genome' );

# make basename for output files
my $basename = $todays_date;
my $output_filename = 'tmp_' . $basename . '.scored.txt';
my $fastq_filename = 'tmp_' . $basename . '.fq';
my $sai_filename = 'tmp_' . $basename . '.sai';

open my $in_fh, '<', $output_filename;
my %output_for;
my @col_names;
my $index_for_crRNA_name;
while( my $line = <$in_fh>){
    chomp $line;
    if( $line =~ m/\A \#/xms ){
        @col_names = split /\t/, $line;
        for ( my $col_i = 0; $col_i < scalar @col_names; $col_i++) {
            if ($col_names[$col_i] eq 'crRNA_name') {
                $index_for_crRNA_name = $col_i;
            }
        }
    }
    else{
        my @values = split /\t/, $line;
        foreach ( my $i = 0; $i < scalar @values; $i++ ){
            $output_for{ $values[$index_for_crRNA_name] }{ $col_names[$i] } = $values[$i];
        }
    }
}

# check some attributes of crRNA:test_chr1:101-123:1 - 3 tests
is( abs($output_for{'crRNA:test_chr1:101-123:1'}{'crRNA_score'} - 0.76) < 0.001, 1, 'check score 1' );
is( $output_for{'crRNA:test_chr1:101-123:1'}{'crRNA_off_target_counts'}, '1|2|2', 'check off_target_counts 1' );
is( $output_for{'crRNA:test_chr1:101-123:1'}{'crRNA_off_target_hits'},
   'test_chr1:201-223:1|test_chr3:101-123:1/test_chr2:101-123:1|test_chr1:1-23:1/test_chr3:201-223:1',
   'check off_target_hits 1' );

# check some attributes of crRNA:test_chr2:41-63:1 - 3 tests
is( abs($output_for{'crRNA:test_chr2:41-63:1'}{'crRNA_score'} - 1) < 0.001, 1, 'check score 2' );
is( $output_for{'crRNA:test_chr2:41-63:1'}{'crRNA_off_target_counts'}, '0|0|0', 'check off_target_counts 2' );
is( $output_for{'crRNA:test_chr2:41-63:1'}{'crRNA_off_target_hits'},
   '||', 'check off_target_hits 2' );


$annotation_file = File::Spec->catfile( 't', 'data', 'Dr-e100_annotation.gff' );
$genome_file = File::Spec->catfile( 't', 'data', 'Danio_rerio.GRCz11.dna_sm.primary_assembly.fa' );

open $tmp_fh, '>', 'crispr.tmp' or die "Couldn't open temp file crispr.tmp to write to!\n";
print $tmp_fh join("\t", qw{ crRNA:24:8727235-8727257:1 crispr_test ENSDARE00000597893 ENSDARG00000059279 tfap2a }, ), "\n";
print $tmp_fh join("\t", qw{ crRNA:24:8727267-8727289:-1 crispr_test ENSDARE00000597893 ENSDARG00000059279 tfap2a }, ), "\n";
close $tmp_fh;

$score_crispr_cmd = join(q{ }, 'perl -I lib scripts/score_crisprs_from_id.pl',
    '--singles', '--species zebrafish', '--num_five_prime_Gs 0',
    '--file_base tmp', '--target_genome', $genome_file,
    "--annotation_file", $annotation_file, 'crispr.tmp',
    '2>', 'tmp.err', );

system( $score_crispr_cmd );
ok( $? >> 8 == 0, 'run score_crisprs_from_id.pl danio genome' );
my $test_output_file = File::Spec->catfile( 't', 'data', 'test_crRNAs-score_from_id-danio.txt' );
system("diff -q $output_filename $test_output_file");
ok( $? >> 8 == 0, 'check score_crisprs_from_id.pl output' );

if (Test::More->builder->is_passing) {
    unlink( 'tmp.err', 'crispr.tmp', $output_filename, $fastq_filename, $sai_filename, );
}

