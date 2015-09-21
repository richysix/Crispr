#!/usr/bin/env perl
# primer_design.t
use warnings;
use strict;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use Getopt::Long;

my $tests = 0;

use Crispr::PrimerDesign;

my $primer_design_obj = Crispr::PrimerDesign->new();

# check crRNA and attributes
# 1 test
isa_ok( $primer_design_obj, 'Crispr::PrimerDesign' );
$tests++;

# check attribute calls - 5 tests
my @attributes = qw( config_file cfg primer3adaptor rebase_file enzyme_collection );

# check method calls - 23 tests
my @methods = qw( _build_config _build_adaptor _build_enzyme_collection
design_primers design_primers_multiple_rounds_nested design_primers_multiple_rounds
sort_and_select_primers fasta_for_repeatmask repeatmask variationmask
get_design_slice_for_target check_slice check_for_unique_re_in_amplicon_and_crRNAs
compare_amplicon_to_crRNA primers_header print_primers_to_file nested_primers_header
print_nested_primers_to_file print_nested_primers_to_file_and_plates
print_hrm_primers_header print_hrm_primers_to_file _increment_rows_columns
print_nested_primers_to_file_and_mixed_plates );

foreach my $attribute ( @attributes ) {
    can_ok( $primer_design_obj, $attribute );
    $tests++;
}

foreach my $method ( @methods ) {
    can_ok( $primer_design_obj, $method );
    $tests++;
}

# test methods
my $primers_header = join("\t", qw{ chromosome target_position strand amp_size round
    pair_name left_id left_seq right_id right_seq
    length1 tm1 length2 tm2 } );

my $test_header = join("\t", $primer_design_obj->primers_header, );
like( $test_header, qr/$primers_header/, 'check primers_header method' );
$tests++;

# test design_primers method
my $sequence = 'GTAAGCCGCGGCGGTGTGTGTGTGTGTGTGTGTTCTCCGTCATCTGTGTTCTGCTGAATGATGAGGACAGACGTGTTTCTCCAGCGGAGGAAGCGTAGAGATGTTCTGCTCTCCATCATCGCTCTTCTTCTGCTCATCTTCGCCATCGTTCATCTCGTCTTCTGCGCTGGACTGAGTTTCCAGGGTTCGAGTTCTGCTCGCGTCCGCCGAGACCTCGAGAATGCGAGTGAGTGTGTGCAGCCACAGTCGTCTGAGTTTCCTGAAGGATTCTTCACGGTGCAGGAGAGGAAAGATGGAGGA';
my $seq2 = 'GTGTATGTAGCTGTACTGTGTTTCGATCTGAAGATCAGCGAGTACGTGATGCAGCGCTTCAGTCCATGCTGCTGGTGTCTGAAACCTCGCGATCGTGACTCAGGCGAGCAGCAGCCTCTAGTGGGCTGGAGTGACGACAGCAGCCTGCGGGTCCAGCGCCGTTCCAGAAATGACAGCGGAATATTCCAGGATGATTCTGGATATTCACATCTATCGCTCAGCCTGCACGGACTCAACGAAATCAGCGACGAGCACAAGAGTGTGTTCTCCATGCCGGATCACGATCTGAAGCGAATCCTG';

my $targets = {
    test_amp1 => {
        chr => '5',
        start => 1,
        end => 700,
        ext_start => 101,
        ext_end => 400,
        strand => '1',
        'ext_amp' => [
            'test_amp1', $sequence, undef, undef, [ [150,1] ], [ [14,20] ], undef, undef
        ],
    },
    test_amp2 => {
        chr => '5',
        start => 50,
        end => 650,
        ext_start => 201,
        ext_end => 500,
        strand => '-1',
        'ext_amp' => [
            'test_amp2', $seq2, undef, undef, [ [150,1] ], [ ], undef, undef
        ],
    }
};

# create tmp config file
open my $tmp_fh, '>', 'config.tmp';

#Primer3-bin     /software/team31/bin/primer3_core
#Primer3-config  /software/team31/bin/primer3_config/

my @names = ( qw{ 1_PRIMER_MIN_SIZE 1_PRIMER_OPT_SIZE 1_PRIMER_MAX_SIZE
    1_PRIMER_MIN_TM 1_PRIMER_OPT_TM 1_PRIMER_MAX_TM 1_PRIMER_PAIR_MAX_DIFF_TM
    1_PRIMER_MIN_GC 1_PRIMER_OPT_GC_PERCENT 1_PRIMER_MAX_GC
    1_PRIMER_LIB_AMBIGUITY_CODES_CONSENSUS 1_PRIMER_EXPLAIN_FLAG
    1_PRIMER_MAX_POLY_X 1_PRIMER_LOWERCASE_MASKING 1_PRIMER_PICK_ANYWAY
    1_PRIMER_NUM_RETURN } );

my @values = ( qw { 18 23 27 53 58 65 10 20 50 80 0 1 4 1 1 1 } );

for my $i ( 0 .. scalar @names - 1 ){
    print {$tmp_fh} join("\t", $names[$i], $values[$i], ), "\n";
}
close( $tmp_fh );

$primer_design_obj = Crispr::PrimerDesign->new( config_file => 'config.tmp', );

#ok( $primer_design_obj->design_primers( $targets, 'ext', '50-300', 1, 1, 1, 1, $adaptors_for, 1 ), 'design_primers method');
ok( $primer_design_obj->design_primers( $targets, 'ext', '50-300', 1, 1, 0, 0, undef, 1 ), 'design_primers method');
$tests++;

unlink( 'config.tmp', 'RM_ext.fa', 'ext_1_primer3.out' );

my @targets = map { $targets->{$_} } keys %{$targets};
open my $fh, '>', '/dev/null';
ok( $primer_design_obj->print_primers_to_file( \@targets, 'ext', $fh, ), 'check print primers to file' );
$tests++;

done_testing( $tests );

