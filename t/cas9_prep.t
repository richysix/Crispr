#!/usr/bin/env perl
# cas9_prep.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;

my $tests;

use Crispr::DB::Cas9Prep;

# make new object with no attributes
my $cas9prep = Crispr::DB::Cas9Prep->new();

isa_ok( $cas9prep, 'Crispr::DB::Cas9Prep');
$tests++;

# check attributes and methods - 5 tests
my @attributes = ( qw{ db_id cas9 prep_type made_by date notes } );

my @methods = ( qw{ _parse_date _build_date } );

foreach my $attribute ( @attributes ) {
    can_ok( $cas9prep, $attribute );
    $tests++;
}
foreach my $method ( @methods ) {
    can_ok( $cas9prep, $method );
    $tests++;
}

# check default attributes
my $db_id = undef;
my $prep_type = 'rna';
my $todays_date_obj = DateTime->now();
is( $cas9prep->db_id, $db_id, 'check db_id default');
$tests++;
is( $cas9prep->prep_type, $prep_type, 'check prep_type default');
$tests++;
is( $cas9prep->date, $todays_date_obj->ymd, 'check date default');
$tests++;

# make mock Cas9 object
my $type = 'ZfnCas9n';
my $species = 's_pyogenes';
my $target_seq = 'NNNNNNNNNNNNNNNNNN';
my $pam = 'NGG';
my $crispr_target_seq = $target_seq . $pam;
my $mock_cas9_object = Test::MockObject->new();
$mock_cas9_object->set_isa( 'Crispr::Cas9' );
$mock_cas9_object->mock( 'type', sub{ return $type } );
$mock_cas9_object->mock( 'species', sub{ return $species } );
$mock_cas9_object->mock( 'target_seq', sub{ return $target_seq } );
$mock_cas9_object->mock( 'PAM', sub{ return $pam } );
$mock_cas9_object->mock( 'crispr_target_seq', sub{ return $crispr_target_seq } );
$mock_cas9_object->mock( 'info', sub{ return ( $type, $species, $crispr_target_seq ) } );

$cas9prep = Crispr::DB::Cas9Prep->new(
    cas9 => $mock_cas9_object,
    prep_type => 'dna',
    made_by => 'crispr_test_user',
    date => '2014-05-24',
    notes => 'Some notes',
);

is( $cas9prep->type, $type, 'check delegation of type attribute');
is( $cas9prep->species, $species, 'check delegation of species attribute');
is( $cas9prep->target_seq, $target_seq, 'check delegation of target_seq attribute');
is( $cas9prep->PAM, $pam, 'check delegation of PAM attribute');
is( $cas9prep->crispr_target_seq, $crispr_target_seq, 'check delegation of crispr_target_seq attribute');
is( $cas9prep->date, '2014-05-24', 'check date set by string');
is( $cas9prep->notes, 'Some notes', 'check notes set by string');
$tests += 7;

# check it throws with non date input
throws_ok { Crispr::DB::Cas9Prep->new( date => '14-05-24' ) } qr/The\sdate\ssupplied\sis\snot\sa\svalid\sformat/, 'non valid date format';
$tests++;

done_testing( $tests );
