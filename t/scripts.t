#!/usr/bin/env perl
# scripts.t
use warnings;
use strict;

BEGIN {
    if( !$ENV{RELEASE_TESTING} ) {
        require Test::More;
        Test::More::plan(
            skip_all => 'these tests are for release candidate testing' );
    }
}

use strict; use warnings;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use File::Spec;
use Test::More;

plan tests => 1 + 3 + 3;

#get current date
use DateTime;
my $date_obj = DateTime->now();
my $todays_date = $date_obj->ymd;


open my $tmp_fh, '>', 'crispr.tmp' or die "Couldn't open temp file crispr.tmp to write to!\n";
print $tmp_fh join("\t", qw{ crRNA:test_chr1:101-123:1 test_target_1 cr_test }, ), "\n";
print $tmp_fh join("\t", qw{ crRNA:test_chr2:41-63:1 test_target_2 cr_test }, ), "\n";
close $tmp_fh;

my $annotation_file = File::Spec->catfile( 't', 'data', 'mock_annotation.gff' );
my $genome_file = File::Spec->catfile( 't', 'data', 'mock_genome.fa' );

my $score_crispr_cmd = join(q{ }, 'perl scripts/score_crisprs_from_id.pl',
    '--singles', '--species zebrafish', '--num_five_prime_Gs 0',
    '--file_base tmp', '--target_genome', $genome_file,
    "--annotation_file", $annotation_file, 'crispr.tmp',
    '2>', '/dev/null', );

# run score_crisprs_from_id.pl script - 1 test
system( $score_crispr_cmd );
ok( $? >> 8 == 0, 'run score_crisprs_from_id.pl' );

# make basename for output files
my $basename = $todays_date;
my $output_filename = 'tmp_' . $basename . '.scored.txt';
my $fastq_filename = 'tmp_' . $basename . '.fq';
my $sai_filename = 'tmp_' . $basename . '.sai';

open my $in_fh, '<', $output_filename;
my %output_for;
my @col_names;
while( my $line = <$in_fh>){
    chomp $line;
    if( $line =~ m/\A \#/xms ){
        @col_names = split /\t/, $line;
    }
    else{
        my @values = split /\t/, $line;
        foreach ( my $i = 0; $i < scalar @values; $i++ ){
            $output_for{ $values[3] }{ $col_names[$i] } = $values[$i];
        }
    }
}

# check some attributes of crRNA:test_chr1:101-123:1 - 3 tests
is( abs($output_for{'crRNA:test_chr1:101-123:1'}{crRNA_score} - 0.76) < 0.001, 1, 'check score 1' );
is( $output_for{'crRNA:test_chr1:101-123:1'}{crRNA_off_target_counts}, '1|2|2', 'check off_target_counts 1' );
is( $output_for{'crRNA:test_chr1:101-123:1'}{crRNA_off_target_hits},
   'test_chr1:201-223:1|test_chr3:101-123:1/test_chr2:101-123:1|test_chr1:1-23:1/test_chr3:201-223:1',
   'check off_target_hits 1' );

# check some attributes of crRNA:test_chr2:41-63:1 - 3 tests
is( abs($output_for{'crRNA:test_chr2:41-63:1'}{crRNA_score} - 1) < 0.001, 1, 'check score 2' );
is( $output_for{'crRNA:test_chr2:41-63:1'}{crRNA_off_target_counts}, '0|0|0', 'check off_target_counts 2' );
is( $output_for{'crRNA:test_chr2:41-63:1'}{crRNA_off_target_hits},
   '||', 'check off_target_hits 2' );

unlink( 'crispr.tmp', $output_filename, $fastq_filename, $sai_filename, );



