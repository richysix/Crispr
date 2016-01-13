#!/usr/bin/env perl
# allele.t
use warnings;
use strict;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use DateTime;

my $tests;

use Crispr::Allele;

# check required attributes
my $chr = '5';
my $pos = 2094757;
my $ref_allele = 'GT';
my $alt_allele = 'GACGATAGACTAGT';
my $allele_number = 31127;

throws_ok {
    Crispr::Allele->new(
        pos => $pos,
        ref_allele => $ref_allele,
        alt_allele => $alt_allele,
    ); } qr/chr.*is\srequired/, 'check chr is required';
throws_ok {
    Crispr::Allele->new(
        chr => $chr,
        ref_allele => $ref_allele,
        alt_allele => $alt_allele,
    ); } qr/pos.*is\srequired/, 'check pos is required';
throws_ok {
    Crispr::Allele->new(
        chr => $chr,
        pos => $pos,
        alt_allele => $alt_allele,
    ); } qr/ref_allele.*is\srequired/, 'check ref_allele is required';
throws_ok {
    Crispr::Allele->new(
        chr => $chr,
        pos => $pos,
        ref_allele => $ref_allele,
    ); } qr/alt_allele.*is\srequired/, 'check alt_allele is required';

$tests += 4;

# make new object
my %args = (
    chr => $chr,
    pos => $pos,
    ref_allele => $ref_allele,
    alt_allele => $alt_allele,
    allele_number => $allele_number,
);

my $allele = Crispr::Allele->new( %args );

isa_ok( $allele, 'Crispr::Allele');
$tests++;

# check attributes and methods - 9 tests
my @attributes = (
    qw{ db_id crisprs chr pos ref_allele alt_allele allele_number percent_of_reads kaspar_assay }
);

my @methods = ( qw{ allele_name add_crispr } );

foreach my $attribute ( @attributes ) {
    can_ok( $allele, $attribute );
    $tests++;
}
foreach my $method ( @methods ) {
    can_ok( $allele, $method );
    $tests++;
}

# check default attributes
my $db_id = undef;
is( $allele->db_id, $db_id, 'check db_id default');
$tests++;

$args{ db_id } = 1,
$allele = Crispr::Allele->new( %args );
is( $allele->db_id, 1, 'check db_id');
is( $allele->chr, $chr, 'check chr');
is( $allele->pos, $pos, 'check pos');
is( $allele->ref_allele, $ref_allele, 'check ref_allele');
is( $allele->alt_allele, $alt_allele, 'check alt_allele');
$tests += 5;

# check allele_name
is( $allele->allele_name, join(":", $chr, $pos, $ref_allele, $alt_allele, ), 'check allele name' );
$tests++;

# check attribute constraints
my %new_args = %args;
$new_args{ chr } = undef;
throws_ok { Crispr::Allele->new( %new_args ) } qr/chr.*Validation\sfailed/, 'check chr throws on undef';
%new_args = %args;
$new_args{ pos } = undef;
throws_ok { Crispr::Allele->new( %new_args ) } qr/pos.*Validation\sfailed/, 'check pos throws on undef';
%new_args = %args;
$new_args{ ref_allele } = undef;
throws_ok { Crispr::Allele->new( %new_args ) } qr/ref_allele.*Not\sa\svalid\sDNA\ssequence/, 'check ref_allele throws on undef';
%new_args = %args;
$new_args{ alt_allele } = undef;
throws_ok { Crispr::Allele->new( %new_args ) } qr/alt_allele.*Not\sa\svalid\sDNA\ssequence/, 'check alt_allele throws on undef';
%new_args = %args;
$new_args{ allele_number } = undef;
throws_ok { Crispr::Allele->new( %new_args ) } qr/allele_number.*Validation\sfailed/, 'check allele_number throws on undef';
$tests += 5;


$args{ chr } = 'Zv9_scaffold';
ok( Crispr::Allele->new( %args ), 'check chr will accept a string' );
%new_args = %args;
$new_args{ pos } = 'Zv9_scaffold';
throws_ok { Crispr::Allele->new( %new_args ) } qr/pos.*Validation\sfailed/, 'check pos throws on Int';
%new_args = %args;
$new_args{ ref_allele } = 'ACGTAE';
throws_ok { Crispr::Allele->new( %new_args ) } qr/ref_allele.*Not\sa\svalid\sDNA\ssequence/, 'check ref_allele throws on non DNA';
%new_args = %args;
$new_args{ ref_allele } = 15;
throws_ok { Crispr::Allele->new( %new_args ) } qr/ref_allele.*Not\sa\svalid\sDNA\ssequence/, 'check ref_allele throws on Int';
%new_args = %args;
$new_args{ alt_allele } = 'ACGTE';
throws_ok { Crispr::Allele->new( %new_args ) } qr/alt_allele.*Not\sa\svalid\sDNA\ssequence/, 'check alt_allele throws on non DNA';
%new_args = %args;
$new_args{ alt_allele } = 15;
throws_ok { Crispr::Allele->new( %new_args ) } qr/alt_allele.*Not\sa\svalid\sDNA\ssequence/, 'check alt_allele throws on Int';
$tests += 6;

# check percent_of_reads attribute
$allele->percent_of_reads( 10.5 );
is( $allele->percent_of_reads, 10.5, 'check value of percent_of_reads' );
%new_args = %args;
$new_args{ percent_of_reads } = 'ten point five';
throws_ok { Crispr::Allele->new( %new_args ) } qr/percent_of_reads.*Validation\sfailed/, 'check percent_of_reads throws on Str';
$tests += 2;

# make mock kaspar assay object
my $mock_kaspar_object = Test::MockObject->new();
$mock_kaspar_object->set_isa( 'Crispr::Kasp' );
$mock_kaspar_object->mock( 'assay_id', sub { return '555.1-7367' } );
$mock_kaspar_object->mock( 'rack_id', sub { return 1 } );
$mock_kaspar_object->mock( 'row_id', sub { return 4 } );
$mock_kaspar_object->mock( 'col_id', sub { return 7 } );

ok( $allele->kaspar_assay( $mock_kaspar_object ), 'add mock kasp object' );
# check attributes
is( $allele->kaspar_id, '555.1-7367', 'check delegation of kaspar_id attribute');
is( $allele->kaspar_rack_id, 1, 'check delegation of kaspar_rack_id attribute');
is( $allele->kaspar_row_id, 4, 'check delegation of kaspar_row_id attribute');
is( $allele->kaspar_col_id, 7, 'check delegation of kaspar_col_id attribute');
$tests += 5;

# test crisprs attribute
# make mock crispr object
my $mock_crispr_object = Test::MockObject->new();
$mock_crispr_object->set_isa( 'Crispr::crRNA' );

# test trying to set attribute directly
throws_ok { $allele->crisprs( $mock_crispr_object ) }
    qr/Cannot assign a value to a read-only accessor/, 'check throws because crispr attribute is read-only';

# test add_crispr method
ok( $allele->add_crispr( $mock_crispr_object ), 'add mock crispr object' );
throws_ok { $allele->add_crispr( $mock_kaspar_object ) }
    qr/Validation failed/, 'check add_crispr throws if argument is not a Crispr::crRNA object';

$tests += 3;


done_testing( $tests );
