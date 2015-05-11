#!/usr/bin/env perl
# kasp.t
use warnings;
use strict;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use DateTime;

my $tests;

use Crispr::DB::Kasp;

# check required attributes
my $assay_id = '555.1-7367';
my $rack_id = 1;
my $row_id = 4;
my $col_id = 7;

throws_ok {
    Crispr::DB::Kasp->new(
        rack_id => $rack_id,
        row_id => $row_id,
        col_id => $col_id,
    ); } qr/assay_id.*is\srequired/, 'check assay_id is required';
throws_ok {
    Crispr::DB::Kasp->new(
        assay_id => $assay_id,
        row_id => $row_id,
        col_id => $col_id,
    ); } qr/rack_id.*is\srequired/, 'check rack_id is required';
throws_ok {
    Crispr::DB::Kasp->new(
        assay_id => $assay_id,
        rack_id => $rack_id,
        col_id => $col_id,
    ); } qr/row_id.*is\srequired/, 'check row_id is required';
throws_ok {
    Crispr::DB::Kasp->new(
        assay_id => $assay_id,
        rack_id => $rack_id,
        row_id => $row_id,
    ); } qr/col_id.*is\srequired/, 'check col_id is required';

$tests += 4;

# make mock Allele object
my $mock_allele = Test::MockObject->new();
$mock_allele->set_isa( 'Crispr::DB::Allele' );
#$mock_allele->mock(  );

# make new object
my %args = (
    assay_id => $assay_id,
    allele => $mock_allele,
    rack_id => $rack_id,
    row_id => $row_id,
    col_id => $col_id,
);

my $kasp = Crispr::DB::Kasp->new( %args );

isa_ok( $kasp, 'Crispr::DB::Kasp');
$tests++;

# check attributes and methods - 5 tests
my @attributes = (
    qw{ assay_id allele rack_id row_id col_id }
);

my @methods = ( qw{  } );

foreach my $attribute ( @attributes ) {
    can_ok( $kasp, $attribute );
    $tests++;
}
foreach my $method ( @methods ) {
    can_ok( $kasp, $method );
    $tests++;
}

# check attributes
is( $kasp->assay_id, $assay_id, 'check assay_id');
isa_ok( $kasp->allele, 'Crispr::DB::Allele', 'check allele' );
is( $kasp->rack_id, $rack_id, 'check rack_id');
is( $kasp->row_id, $row_id, 'check row_id');
is( $kasp->col_id, $col_id, 'check col_id');
$tests += 5;

# check attribute constraints
my %new_args = %args;
$new_args{ assay_id } = undef;
throws_ok { Crispr::DB::Kasp->new( %new_args ) } qr/assay_id.*Validation\sfailed/, 'check assay_id throws on undef';
%new_args = %args;
$new_args{ rack_id } = undef;
throws_ok { Crispr::DB::Kasp->new( %new_args ) } qr/rack_id.*Validation\sfailed/, 'check rack_id throws on undef';
%new_args = %args;
$new_args{ row_id } = undef;
throws_ok { Crispr::DB::Kasp->new( %new_args ) } qr/row_id.*Validation\sfailed/, 'check row_id throws on undef';
%new_args = %args;
$new_args{ col_id } = undef;
throws_ok { Crispr::DB::Kasp->new( %new_args ) } qr/col_id.*Validation\sfailed/, 'check col_id throws on undef';
%new_args = %args;
$new_args{ allele } = undef;
throws_ok { Crispr::DB::Kasp->new( %new_args ) } qr/allele.*Validation\sfailed/, 'check allele throws on undef';
$tests += 5;

%new_args = %args;
$new_args{ rack_id } = 'string';
throws_ok { Crispr::DB::Kasp->new( %new_args ) } qr/rack_id.*Validation\sfailed/, 'check rack_id throws on Str';
%new_args = %args;
$new_args{ row_id } = 'string';
throws_ok { Crispr::DB::Kasp->new( %new_args ) } qr/row_id.*Validation\sfailed/, 'check row_id throws on Str';
%new_args = %args;
$new_args{ col_id } = 'string';
throws_ok { Crispr::DB::Kasp->new( %new_args ) } qr/col_id.*Validation\sfailed/, 'check col_id throws on Str';
%new_args = %args;
$new_args{ allele } = 'Allele';
throws_ok { Crispr::DB::Kasp->new( %new_args ) } qr/allele.*Validation\sfailed/, 'check allele throws on Str';
$tests += 4;

done_testing( $tests );
