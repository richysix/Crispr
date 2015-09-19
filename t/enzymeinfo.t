#!/usr/bin/env perl
# enzymeinfo.t
use warnings;
use strict;

use Test::More;
use Test::Exception;
use Test::Warn;
use List::MoreUtils qw( any none );

my $number_of_tests_run = 0;
#plan tests => 1 + 4 + 5;

use Crispr::EnzymeInfo;

my $enzyme_info_obj = Crispr::EnzymeInfo->new();

# check crRNA and attributes
# 1 test
isa_ok( $enzyme_info_obj, 'Crispr::EnzymeInfo' );
$number_of_tests_run++;

# check attributes and methods 4 + 5 tests
my @attributes = ( qw{ crRNA analysis amplicon_analysis uniq_in_both } );
my @methods = qw( proximity_to_cut_site _construct_enzyme_site_regex_from_target_seq 
    _build_uniq_in_both unique_cutters unique_cutters_in_amplicon
);

foreach my $attribute ( @attributes ) {
    can_ok( $enzyme_info_obj, $attribute );
    $number_of_tests_run++;
}

foreach my $method ( @methods ) {
    can_ok( $enzyme_info_obj, $method );
    $number_of_tests_run++;
}

done_testing( $number_of_tests_run );

## TO DO: write some more tests.
