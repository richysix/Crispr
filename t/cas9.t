#!/usr/bin/env perl
# cas9.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;

my $tests;

use Crispr::Cas9;

# make new object with no attributes
my $cas9 = Crispr::Cas9->new();

isa_ok( $cas9, 'Crispr::Cas9');
$tests++;

# check attributes and methods - 7 + 8 tests
my @attributes = ( qw{ db_id type species target_seq PAM
                  vector name } );

my @methods = ( qw{ _parse_species name info crispr_target_seq _build_target_seq
               _build_PAM _build_name _build_vector } );

foreach my $attribute ( @attributes ) {
    can_ok( $cas9, $attribute );
    $tests++;
}
foreach my $method ( @methods ) {
    can_ok( $cas9, $method );
    $tests++;
}

# check default attributes
my $type = 'ZfnCas9n';
my $species = 's_pyogenes';
my $target_seq = 'NNNNNNNNNNNNNNNNNN';
my $pam = 'NGG';
my $vector = 'pCS2';
my $name = join(q{-}, $vector, $type );
my $crispr_target_seq = $target_seq . $pam;
is( $cas9->type, $type, 'check type default');
$tests++;
is( $cas9->species, $species, 'check species default');
$tests++;
is( $cas9->target_seq, $target_seq, 'check target_seq default');
$tests++;
is( $cas9->PAM, $pam, 'check PAM default');
$tests++;
is( $cas9->crispr_target_seq, $crispr_target_seq, 'check crispr_target_seq default');
$tests++;
is( $cas9->vector, $vector, 'check type default');
$tests++;
is( $cas9->name, $name, 'check name default');
$tests++;

my $cas9_tmp = Crispr::Cas9->new( species => 'new species' );
is( $cas9_tmp->target_seq, $target_seq, 'check target_seq default for unknown species');
is( $cas9_tmp->PAM, $pam, 'check PAM default for unknown species');
$tests += 2;

my @test_info = ( $type, $species, $crispr_target_seq, );
my $reg_str = join("\\s", @test_info);
like( join("\t", $cas9->info ), qr/$reg_str/, 'info' );
$tests++;

# check attribute validation
throws_ok { Crispr::Cas9->new( target_seq => 'GACTAE' ); } qr/Not\sa\svalid\sDNA\ssequence/, 'check throws on non-DNA target_seq';
throws_ok { Crispr::Cas9->new( PAM => 'GACTAE' ); } qr/Not\sa\svalid\sDNA\ssequence/, 'check throws on non-DNA PAM';
throws_ok { Crispr::Cas9->new( type => 'cas9_gfp' ); } qr/Validation\sfailed/, 'check throws on cas9 type not in ENUM';
$tests += 3;

# check _parse_species
my $cas9_tmp = Crispr::Cas9->new( species => 'streptococcus_pyogenes' );
is( $cas9_tmp->species, 's_pyogenes', 'check parse_species' );
$tests++;
$cas9_tmp = Crispr::Cas9->new( species => 'new species' ); 
is( $cas9_tmp->species, 'new species', 'check parse_species with unknown species' );
$tests++;

throws_ok { Crispr::Cas9->new( species => '' ) } qr/Validation\sfailed/, 'check throws on undef species';
$tests++;

done_testing( $tests );