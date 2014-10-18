#!/usr/bin/env perl
# subplex.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use DateTime;

my $tests;

use Crispr::DB::Subplex;

# make new object with no attributes
my $subplex = Crispr::DB::Subplex->new();

isa_ok( $subplex, 'Crispr::DB::Subplex');
$tests++;

# check attributes and methods - 4 tests
my @attributes = (
    qw{ db_id plex injection_pool plate_num }
);

my @methods = ( qw{ } );

foreach my $attribute ( @attributes ) {
    can_ok( $subplex, $attribute );
    $tests++;
}
foreach my $method ( @methods ) {
    can_ok( $subplex, $method );
    $tests++;
}

# check default attributes
my $db_id = undef;
is( $subplex->db_id, $db_id, 'check db_id default');
$tests++;

my $mock_plex_object = Test::MockObject->new();
$mock_plex_object->set_isa( 'Crispr::DB::Plex' );

my $mock_inj_pool_object = Test::MockObject->new();
$mock_inj_pool_object->set_isa( 'Crispr::DB::InjectionPool' );

$subplex = Crispr::DB::Subplex->new(
    db_id => 1,
    plex => $mock_plex_object,
    injection_pool => $mock_inj_pool_object,
    plate_num => 1,
);

is( $subplex->db_id, 1, 'check db_id');
is( $subplex->plex, $mock_plex_object, 'check plex');
is( $subplex->injection_pool, $mock_inj_pool_object, 'check injection_pool');
is( $subplex->plate_num, 1, 'check plate_num');
$tests += 4;

throws_ok { Crispr::DB::Subplex->new( plate_num => 5 ) } qr/Validation\sfailed/, 'check throws if plate num is not 1, 2, 3 or 4';
$tests++;

done_testing( $tests );
