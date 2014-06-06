#!/usr/bin/env perl
# enzymeinfo.t
use Test::More;
use Test::Exception;
use Test::Warn;
use List::MoreUtils qw( any none );

#my $number_of_tests_run = 0;
plan tests => 1 + 8;

use Crispr::EnzymeInfo;

my $enzyme_info_obj = Crispr::EnzymeInfo->new();

# check crRNA and attributes
# 1 test
isa_ok( $enzyme_info_obj, 'Crispr::EnzymeInfo' );

# check method calls 8 tests
my @methods = qw( unique_cutters analysis amplicon_analysis
    unique_cutters_in_amplicon uniq_in_both proximity_to_cut_site
    _construct_enzyme_site_regex_from_target_seq _parse_uniq_in_both
);

foreach my $method ( @methods ) {
    can_ok( $enzyme_info_obj, $method );
    $number_of_tests_run++;
}

## TO DO: write some more tests.
