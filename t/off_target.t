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

plan tests => 1 + 8 + 10;

use Crispr::OffTarget;

my $off_target = Crispr::OffTarget->new();

# check crRNA and attributes
# 1 test
isa_ok( $off_target, 'Crispr::OffTarget' );

# check method calls 8 tests
my @attributes = ( qw{ crRNA_name chr start end strand
    mismatches annotation position } );

foreach my $attribute ( @attributes ) {
    can_ok( $off_target, $attribute );
}

# check type constraints - 10 tests
ok( $off_target = Crispr::OffTarget->new(
        crRNA_name => 'crRNA:test_chr1:101-123:1',
        chr => 'test_chr1',
        start => 201,
        end => 223,
        strand => '1',
        mismatches => 2,
        annotation => 'exon',
    ), 'Object creation' );

throws_ok { Crispr::OffTarget->new( crRNA_name => [] ) } qr/Validation\sfailed/, 'non String crRNA_name';
throws_ok { Crispr::OffTarget->new( start => [] ) } qr/Validation\sfailed/, 'non Int start';
throws_ok { Crispr::OffTarget->new( end => [] ) } qr/Validation\sfailed/, 'non Int end';
throws_ok { Crispr::OffTarget->new( strand => '-2' ) } qr/Validation\sfailed/, 'non 1 or -1 strand';

throws_ok { Crispr::OffTarget->new( mismatches => [] ) } qr/Validation\sfailed/, 'non Int mismatches';
throws_ok { Crispr::OffTarget->new( mismatches => 'five' ) } qr/Validation\sfailed/, 'non Int mismatches';

throws_ok { Crispr::OffTarget->new( annotation => [] ) } qr/Validation\sfailed/, 'non Int mismatches';
throws_ok { Crispr::OffTarget->new( annotation => 'extron' ) } qr/Validation\sfailed/, 'annotation - not exon, intron or nongenic';

is( $off_target->position, 'test_chr1:201-223:1', 'check position' );
