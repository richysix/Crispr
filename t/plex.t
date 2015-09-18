#!/usr/bin/env perl
# plex.t
use warnings;
use strict;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use DateTime;

my $tests;

use Crispr::DB::Plex;

# make new object with no attributes
my $plex = Crispr::DB::Plex->new();

isa_ok( $plex, 'Crispr::DB::Plex');
$tests++;

# check attributes and methods - 5 tests
my @attributes = (
    qw{ db_id plex_name run_id analysis_started analysis_finished }
);

my @methods = ( qw{ } );

foreach my $attribute ( @attributes ) {
    can_ok( $plex, $attribute );
    $tests++;
}
foreach my $method ( @methods ) {
    can_ok( $plex, $method );
    $tests++;
}

# check default attributes
my $db_id = undef;
is( $plex->db_id, $db_id, 'check db_id default');
$tests++;

$plex = Crispr::DB::Plex->new(
    db_id => 1,
    plex_name => '8',
    run_id => 56,
    analysis_started => '2014-09-30',
    analysis_finished => '2014-10-01',
);

is( $plex->db_id, 1, 'check db_id');
is( $plex->plex_name, '8', 'check plex_name');
is( $plex->run_id, 56, 'check run_id');
is( $plex->analysis_started, '2014-09-30', 'check analysis_started');
is( $plex->analysis_finished, '2014-10-01', 'check analysis_finished');
$tests += 5;

$plex = Crispr::DB::Plex->new(
    db_id => 1,
    plex_name => 'MPX20',
    run_id => 56,
    analysis_started => '2014-09-30',
    analysis_finished => '2014-10-01',
);

is( $plex->plex_name, 'mpx20', 'check plex_name is returned lowercase');
$tests += 1;


done_testing( $tests );
