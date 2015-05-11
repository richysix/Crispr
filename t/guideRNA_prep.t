#!/usr/bin/env perl
# guideRNA_prep.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use DateTime;

my $tests;

use Crispr::DB::GuideRNAPrep;

# need new mock crRNA object
my $mock_crRNA_object = Test::MockObject->new();
$mock_crRNA_object->set_isa( 'Crispr::crRNA' );
$mock_crRNA_object->mock( 'crRNA_id', sub { return 1 } );
$mock_crRNA_object->mock( 'crRNA_name', sub { return 'crRNA:7:26374-26396:-1' } );

# make new object
my $stock_concentration = 20;
my $injection_concentration = 10;
my $made_by = 'crispr_test';
my $type = 'sgRNA';
my $date = DateTime->now();

my %args = (
    crRNA => $mock_crRNA_object,
    type => $type,
    stock_concentration => $stock_concentration,
    injection_concentration => $injection_concentration,
    made_by => $made_by,
    date => $date,
);

my $guideRNA_prep = Crispr::DB::GuideRNAPrep->new( %args );

isa_ok( $guideRNA_prep, 'Crispr::DB::GuideRNAPrep');
$tests++;

# check attributes and methods - 12 tests
my @attributes = (
    qw{ db_id crRNA type stock_concentration injection_concentration made_by
        date well }
);

my @methods = ( qw{  } );

foreach my $attribute ( @attributes ) {
    can_ok( $guideRNA_prep, $attribute );
    $tests++;
}
foreach my $method ( @methods ) {
    can_ok( $guideRNA_prep, $method );
    $tests++;
}

# check attributes
is( $guideRNA_prep->crRNA, $mock_crRNA_object, 'check crRNA');
is( $guideRNA_prep->stock_concentration, $stock_concentration, 'check stock_concentration');
is( $guideRNA_prep->made_by, $made_by, 'check made_by');
is( $guideRNA_prep->date, $date->ymd, 'check date');
$tests += 4;

# check attribute constraints
%new_args = %args;
$new_args{ crRNA } = 'crRNA:7:26374-26396:-1';
throws_ok { Crispr::DB::GuideRNAPrep->new( %new_args ) } qr/crRNA.*Validation\sfailed/, 'check crRNA throws on Str';
%new_args = %args;
$new_args{ stock_concentration } = 'twenty';
throws_ok { Crispr::DB::GuideRNAPrep->new( %new_args ) } qr/stock_concentration.*Validation\sfailed/, 'check stock_concentration throws on Str';
%new_args = %args;
$new_args{ date } = '14-09-30';
throws_ok { Crispr::DB::GuideRNAPrep->new( %new_args ) } qr/The\sdate\ssupplied\sis\snot\sa\svalid\sformat/, 'check date throws on non valid date';
$tests += 3;

# check date accepts string in yyyy-mm-dd format
$new_args{ date } = '2014-09-30';
ok( Crispr::DB::GuideRNAPrep->new( %new_args ), 'check date accepts string in yyyy-mm-dd format' );
$tests++;

done_testing( $tests );
