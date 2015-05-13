#!/usr/bin/env perl
# target.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use English qw( -no_match_vars );
use Data::Dumper;

use DateTime;
#get current date
my $date_obj = DateTime->now();
my $todays_date = $date_obj->ymd;

plan tests => 4 + 2 + 1 + 17 + 4 + 4 + 2 + 5 + 6 + 6 + 2 + 8 + 2 + 2 + 2 + 2 + 6 + 9 + 4;

my $species = 'zebrafish';

use Crispr::Target;

# make a new target - designed should be undef
# have not defined crRNAs
my $target = Crispr::Target->new(
    target_name => 'KAT5_exon1',
    assembly => 'Zv9',
    chr => '5',
    start => 18067321,
    end => 18083466,
    strand => '-1',
    species => 'danio_rerio',
    requires_enzyme => 1,
    gene_id => 'ENSDARG00000090174',
    gene_name => 'KAT5 (1 of 2)',
    requestor => 'crispr_test',
    ensembl_version => 71,
); 

## make a new Mock cRNAs object
use Crispr::crRNA;
my @crRNAs;
for ( 1..3 ){
    my $crRNA = Test::MockObject->new();
    $crRNA->set_isa('Crispr::crRNA');
    $crRNA->mock( 'target', sub { return $target } );
    #my $crRNA = Crispr::crRNA->new(
    #    target => $target,
    #);
    push @crRNAs, $crRNA;
}
$target->crRNAs( \@crRNAs );

# check crRNAs - 4 tests
isa_ok( $target->crRNAs, 'ARRAY', 'crRNAs' );
#print Dumper( $target->crRNAs );
#print Dumper( $target );
foreach( @{ $target->crRNAs } ){
    isa_ok( $_, 'Crispr::crRNA', 'crRNA' );
}

# make a new Mock target adaptor object
my $ta = Test::MockObject->new();
$ta->set_isa('Crispr::DB::TargetAdaptor');
$target->target_adaptor( $ta );

# new target without a chr, assembly, strand, gene_id, gene_name, ensembl_version
my $target_2 = Crispr::Target->new(
    target_name => 'gfp_50_100',
    start => 50,
    end => 60,
    species => 'Aequorea_victoria',
    requestor => 'crispr_test',
    designed => '2012-07-18',
);

# check target_adaptor - 2 tests
isa_ok( $target->target_adaptor, 'Crispr::DB::TargetAdaptor', 'target_adaptor');
is( $target_2->target_adaptor, undef, 'target_adaptor2');

# check Target and attributes
# 1 test
isa_ok( $target, 'Crispr::Target' );

# check method calls 17 tests
my @methods = qw( target_id target_name assembly chr start
    end strand species requires_enzyme gene_id
    gene_name requestor ensembl_version designed target_adaptor
    region info );

foreach my $method ( @methods ) {
    can_ok( $target, $method );
}

# 4 tests - check type constraints for target_id
is( $target->target_id, undef, 'Get id' );

$tmp_target = Crispr::Target->new( target_id => '1' );
is( $tmp_target->target_id, '1', 'Set id' );
throws_ok { Crispr::Target->new( target_id => 'string') } qr/Validation failed/ms, 'string id';
throws_ok { Crispr::Target->new( target_id => '' ) } qr/Validation failed/ms, 'Empty string id';

# 4 tests - check type constraints for target_name
is( $target->target_name, 'KAT5_exon1', 'Get target_name' );
throws_ok { Crispr::Target->new( target_name => '' ) } qr/Attribute is empty/, 'empty target_name';
$tmp_target = Crispr::Target->new( target_name => 1 ); #coerced to string '1'
is( $tmp_target->target_name, '1', 'Number as string');
is( $target_2->target_name, 'gfp_50_100', 'Name 2');

# assembly - 2 tests
is( $target->assembly, 'Zv9', 'Assembly1');
is( $target_2->assembly, undef, 'Assembly2');

# chr - 5 tests
is( $target->chr, '5', 'Get chr' );
$tmp_target = Crispr::Target->new( chr => '' );
is( $tmp_target->chr, undef, 'Empty string chr' );
$tmp_target = Crispr::Target->new( chr => 'Zv9_NA' );
is( $tmp_target->chr, 'Zv9_NA', 'Set chr Zv9_NA');
$tmp_target = Crispr::Target->new( chr => '5' );
is( $tmp_target->chr, '5', 'Set chr 5');

is( $target_2->chr, undef, 'Get undef chr' );

# start and end - 6 tests
is( $target->start, 18067321, 'Get start' );
is( $target->end, 18083466, 'Get end' );
throws_ok { Crispr::Target->new( start => '' ) } qr/Validation failed/, 'Empty start';
throws_ok { Crispr::Target->new( end => '' ) } qr/Validation failed/, 'Empty end';
is( $target_2->start, 50, 'Start2');
is( $target_2->end, 60, 'Start2');

# check strand - 6 tests
is( $target->strand, '-1', 'Get strand');
# check default value
is( $tmp_target->strand, '1', 'Check default strand' );
throws_ok { Crispr::Target->new( strand => '2' ) } qr/Validation failed/, 'Not a Strand';
is( $target_2->strand, '1', 'Strand2');
# check parse_strand
$tmp_target = Crispr::Target->new( strand => '+' );
is( $tmp_target->strand, '1', 'Check parse + strand' );
$tmp_target = Crispr::Target->new( strand => '-' );
is( $tmp_target->strand, '-1', 'Check parse - strand' );

# species - 2 tests
is( $target->species, 'danio_rerio', 'species1');
is( $target_2->species, 'Aequorea_victoria', 'species2');

# requires_enzyme - 8 tests
is( $target->requires_enzyme, 'y', 'Enzyme1');
is( $target_2->requires_enzyme, 'n', 'check default Enzyme');
$target->requires_enzyme('n');
is( $target->requires_enzyme, 'n', 'check setting enzyme with n');
$target->requires_enzyme('y');
is( $target->requires_enzyme, 'y', 'check setting enzyme with y');
$target->requires_enzyme(0);
is( $target->requires_enzyme, 'n', 'check setting enzyme with 0');
$target->requires_enzyme(1);
is( $target->requires_enzyme, 'y', 'check setting enzyme with 1');

warning_like { $target->requires_enzyme('cheese') }
    qr/The\svalue\sfor\s\S+\sis\snot\sa\srecognised\svalue.\sShould\sbe\sone\sof\s1,\s0,\sy\sor\sn./,
    'check setting enzyme with something else warns';
is( $target->requires_enzyme(undef), 'y', 'check setting enzyme to undef changes nothing');

# gene_id - 2 tests
is( $target->gene_id, 'ENSDARG00000090174', 'Gene id 1');
is( $target_2->gene_id, undef, 'Gene id 2');

# gene_name - 2 tests
is( $target->gene_name, 'KAT5_1_of_2', 'Gene name 1');
is( $target_2->gene_name, undef, 'Gene name 2');

# requestor - 2 tests
is( $target->requestor, 'crispr_test', 'requestor1');
is( $target_2->requestor, 'crispr_test', 'requestor2');

# ensembl_version - 2 tests
is( $target->ensembl_version, 71, 'ensembl_version1');
is( $target_2->ensembl_version, undef, 'ensembl_version2');

# designed - 6 tests
is( $target->designed, undef, 'check default date' );
$target->designed( '2012-05-23' );
is( $target->designed, '2012-05-23', 'check date set' );
# set date with DateTime object
$target->designed( $date_obj );
is( $target->designed, $todays_date, 'check date set using DateTime object' );

throws_ok { $target->designed( '20120228' ) } qr/valid format/, 'Invalid date format';
throws_ok { $target->designed( '2012-02-30' ) } qr/Invalid/, 'Impossible date';

is( $target_2->designed, '2012-07-18', 'designed2');

# 9 tests - check output of non attribute methods
is( $target->region, '5:18067321-18083466:-1', 'check region');
is( $target_2->region, '50-60:1', 'Get region without chr');
is( $target->length, 16146, 'check length' );

like( join("\t", $target->summary ),
    qr/KAT5_exon1\tENSDARG00000090174\tKAT5_1_of_2\tcrispr_test/, 'check summary 1' );
like( join("\t", $target_2->summary ),
    qr/gfp_50_100\tNULL\tNULL\tcrispr_test/, 'check summary 2' );
like( join("\t", $target->info ),
    qr/\A NULL\tKAT5_exon1\tZv9\t5\t18067321\t18083466\t-1\tdanio_rerio\ty\tENSDARG00000090174\tKAT5_1_of_2\tcrispr_test\t71\t$todays_date \z/xms, 'check info 1' );
like( join("\t", $target_2->info ),
    qr/\A NULL\tgfp_50_100\tNULL\tNULL\t50\t60\t1\tAequorea_victoria\tn\tNULL\tNULL\tcrispr_test\tNULL\t2012-07-18 \z/xms, 'check info 2' );

$tmp_target = Crispr::Target->new(
    target_id => 1,
    target_name => 'SLC39A14',
    assembly => 'Zv9',
    chr => '5',
    start => 18067321,
    end => 18083466,
    strand => '-1',
    requires_enzyme => 1,
    gene_id => 'ENSDARG00000090174',
    gene_name => 'SLC39A14',
    ensembl_version => 71,
);

like( join("\t", $tmp_target->summary ),
    qr/SLC39A14\tENSDARG00000090174\tSLC39A14\tNULL/, 'check summary 3' );
like( join("\t", $tmp_target->info ),
    qr/\A 1\tSLC39A14\tZv9\t5\t18067321\t18083466\t-1\tNULL\ty\tENSDARG00000090174\tSLC39A14\tNULL\t71\tNULL \z/xms, 'check info 3' );

# create object with hash and hash_ref
my %args = (
    target_name => 'gfp_50_100',
    start => 50,
    end => 60,
    species => 'Aequorea_victoria',
    requestor => 'crispr_test',
);

my $target_3 = Crispr::Target->new( %args );
my $target_4 = Crispr::Target->new( \%args );

# check target_name and chr set properly - 4 tests
is( $target_3->target_name, 'gfp_50_100', 'check target_name is set with hash calling style' );
is( $target_4->target_name, 'gfp_50_100', 'check target_name is set with hashref calling style' );
is( $target_3->chr, undef, 'check chr is set with hash calling style' );
is( $target_4->chr, undef, 'check chr is set with hashref calling style' );

