#!/usr/bin/env perl
# target_adaptor.t
use warnings;
use strict;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::DatabaseRow;
use Test::MockObject;
use Data::Dumper;
use List::MoreUtils qw{ any };
use Readonly;

use Crispr::DB::TargetAdaptor;

# Number of tests
Readonly my $TESTS_IN_COMMON => 1 + 20 + 2 + 14 + 14 + 15 + 13 + 1 + 13 + 13;
Readonly my %TESTS_FOREACH_DBC => (
    mysql => $TESTS_IN_COMMON,
    sqlite => $TESTS_IN_COMMON,
);
plan tests => $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite};

use DateTime;
#get current date
my $date_obj = DateTime->now();
my $todays_date = $date_obj->ymd;

use Bio::EnsEMBL::Registry;
Bio::EnsEMBL::Registry->load_registry_from_db(
  -host    => 'ensembldb.ensembl.org',
  -user    => 'anonymous',
);

my $species = 'zebrafish';
my $slice_ad = Bio::EnsEMBL::Registry->get_adaptor( $species, 'core', 'slice' );

# Module with a function for creating an empty test database
# and returning a database connection
use TestDB;

if( !$ENV{MYSQL_DBNAME} || !$ENV{MYSQL_DBUSER} || !$ENV{MYSQL_DBPASS} ){
    die "The following environment variables need to be set for connecting to the database!\n",
        "MYSQL_DBNAME, MYSQL_DBUSER, MYSQL_DBPASS"; 
}

my %db_connection_params = (
    mysql => {
        driver => 'mysql',
        dbname => $ENV{MYSQL_DBNAME},
        host => $ENV{MYSQL_DBHOST} || '127.0.0.1',
        port => $ENV{MYSQL_DBPORT} || 3306,
        user => $ENV{MYSQL_DBUSER},
        pass => $ENV{MYSQL_DBPASS},
    },
    sqlite => {
        driver => 'sqlite',
        dbfile => 'test.db',
        dbname => 'test',
    }
);

# TestDB creates test database, connects to it and gets db handle
my @db_connections;
foreach my $driver ( keys %db_connection_params ){
    push @db_connections, TestDB->new( $db_connection_params{$driver} );
}

SKIP: {
    skip 'No database connections available', $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite} if !@db_connections;
    
    if( @db_connections == 1 ){
        skip 'Only one database connection available', $TESTS_FOREACH_DBC{sqlite} if $db_connections[0]->driver eq 'mysql';
        skip 'Only one database connection available', $TESTS_FOREACH_DBC{mysql} if $db_connections[0]->driver eq 'sqlite';
    }
}

my $comment_regex = qr/#/;
my @attributes = qw{ target_id target_name assembly chr start end strand
    species requires_enzyme gene_id gene_name requestor ensembl_version
    designed };

my @required_attributes = qw{ target_name start end strand requires_enzyme
    requestor };

my @columns;

foreach my $db_connection ( @db_connections ){
    my $driver = $db_connection->driver;
    my $dbh = $db_connection->connection->dbh;
    # $dbh is a DBI database handle
    local $Test::DatabaseRow::dbh = $dbh;
    
    # make a mock DBConnection object
    my $mock_db_connection = Test::MockObject->new();
    $mock_db_connection->set_isa( 'Crispr::DB::DBConnection' );
    $mock_db_connection->mock( 'dbname', sub { return $db_connection->dbname } );
    $mock_db_connection->mock( 'connection', sub { return $db_connection->connection } );
    
    # make a new real Target Adaptor
    my $target_adaptor = Crispr::DB::TargetAdaptor->new( db_connection => $mock_db_connection, );
    # 1 test
    isa_ok( $target_adaptor, 'Crispr::DB::TargetAdaptor', "$driver: check object class is ok" );

    # check attributes and methods - 3 + 17 tests
    my @object_attributes = ( qw{ dbname db_connection connection } );
    
    my @methods = (
        qw{ store store_targets update_designed fetch_by_id fetch_by_ids
            fetch_by_name_and_requestor fetch_by_names_and_requestors fetch_by_crRNA fetch_by_crRNA_id _fetch
            _make_new_object_from_db _make_new_target_from_db delete_target_from_db check_entry_exists_in_db fetch_rows_expecting_single_row
            fetch_rows_for_generic_select_statement _db_error_handling }
    );
    
    foreach my $attribute ( @object_attributes ) {
        can_ok( $target_adaptor, $attribute );
    }
    foreach my $method ( @methods ) {
        can_ok( $target_adaptor, $method );
    }
    
    # make a new mock target object
    my $mock_target = Test::MockObject->new();
    $mock_target->set_isa( 'Crispr::Target' );
    my $t_id;
	$mock_target->mock('target_id', sub{ my @args = @_; if( $_[1] ){ $t_id = $_[1] } return $t_id; } );
	$mock_target->mock('target_name', sub { return 'SLC39A14' } );
	$mock_target->mock('assembly', sub { return 'Zv9' } );
	$mock_target->mock('chr', sub { return '5' } );
	$mock_target->mock('start', sub { return 18067321 } );
	$mock_target->mock('end', sub { return 18083466 } );
	$mock_target->mock('strand', sub { return '-1' } );
	$mock_target->mock('species', sub { return 'danio_rerio' } );
	$mock_target->mock('requires_enzyme', sub { return 'n' } );
	$mock_target->mock('gene_id', sub { return 'ENSDARG00000090174' } );
	$mock_target->mock('gene_name', sub { return 'SLC39A14' } );
	$mock_target->mock('requestor', sub { return 'crispr_test' } );
	$mock_target->mock('ensembl_version', sub { return 71 } );
	$mock_target->mock('designed', sub { return undef } );
    
    # store target - 2 tests
    my $count = 0;
    $mock_target = $target_adaptor->store($mock_target);
    $count++;
    # 1 tests
    is( $mock_target->target_id, $count, "$driver: Check primary key" );
    
    # check database row
    # 1 test
    row_ok(
       table => 'target',
       where => [ target_id => 1 ],
       tests => {
           'eq' => {
                target_name => 'SLC39A14',
                assembly => 'Zv9',
                chr  => '5',
                strand => '-1',
                species => 'danio_rerio',
                requires_enzyme => 'n',
                gene_id => 'ENSDARG00000090174',
                gene_name => 'SLC39A14',
                requestor => 'crispr_test',
                designed => undef,
           },
           '==' => {
                start  => 18067321,
                end    => 18083466,
                ensembl_version => 71,
           },
       },
       label => "$driver: Target stored",
    );
    
    # make a mock crRNA and store it to test retrieval by crRNA
    my $mock_crRNA = Test::MockObject->new();
    $mock_crRNA->set_isa('Crispr::crRNA');
    my $c_id;
    $mock_crRNA->mock('target_id', sub { return 1 } );
    $mock_crRNA->mock('crRNA_id', sub { my @args = @_; if( $_[1] ){ $c_id = $_[1] } return $c_id; } );
    $mock_crRNA->mock('name', sub { return "5:18067351-18067373:1" } );
    $mock_crRNA->mock('chr', sub { return '5' } );
    $mock_crRNA->mock('start', sub { return 18067351 } );
    $mock_crRNA->mock('end', sub { return 18067373 } );
    $mock_crRNA->mock('strand', sub { return '1' } );
    $mock_crRNA->mock('sequence', sub { return 'GGCACCTGATAGACTAGATGAGG' } );
    $mock_crRNA->mock('five_prime_Gs', sub { return 2 } );
    $mock_crRNA->mock('score', sub { return 0.9 } );
    $mock_crRNA->mock('off_target_score', sub { return 1 } );
    $mock_crRNA->mock('coding_score', sub { return 0.9 } );
    
    my $statement = "insert into crRNA values( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    
    my $sth = $dbh->prepare($statement);
    $sth->execute($mock_crRNA->crRNA_id, $mock_crRNA->name,
        $mock_crRNA->chr, $mock_crRNA->start, $mock_crRNA->end, $mock_crRNA->strand,
        $mock_crRNA->sequence, $mock_crRNA->five_prime_Gs,
        $mock_crRNA->score, $mock_crRNA->off_target_score, $mock_crRNA->coding_score,
        $mock_crRNA->target_id, undef, undef,
    );    
    
    # test _fetch method - 14 tests
    my $targets;
    ok( $targets = $target_adaptor->_fetch( 'target_id = ?', [ 1 ] ), "$driver: test _fetch method" );
    check_object_attributes( $targets->[0], $mock_target, $driver, '_fetch' );
    
    #test fetch_by_crRNA_id - 14 tests
    my $target;
    ok( $target = $target_adaptor->fetch_by_crRNA_id( 1 ), "$driver: test fetch_by_crRNA_id method" );
    check_object_attributes( $target, $mock_target, $driver, 'fetch_by_crRNA_id' );
    
    #test fetch_by_crRNA - 15 tests
    throws_ok { $target_adaptor->fetch_by_crRNA( $mock_crRNA ) }
        qr/Method: fetch_by_crRNA. Cannot fetch target because crRNA_id is not defined/, 
        "$driver: test fetch_by_crRNA method";
    $c_id = 1;
    ok( $target = $target_adaptor->fetch_by_crRNA( $mock_crRNA ), "$driver: test fetch_by_crRNA method" );
    check_object_attributes( $target, $mock_target, $driver, 'fetch_by_crRNA' );

    # fetch target by name and requestor from database - 13 tests
    my $target_3 = $target_adaptor->fetch_by_name_and_requestor( 'SLC39A14', 'crispr_test' );
    check_object_attributes( $target_3, $mock_target, $driver, 'fetch_by_name_and_requestor' );
    
    # new target without a assembly, chr, strand, species, gene_id, gene_name, ensembl_version, and designed.
    my $mock_target_2 = Test::MockObject->new();
    $mock_target_2->set_isa( 'Crispr::Target' );
    my $t2_id;
	$mock_target_2->mock('target_id', sub{ my @args = @_; if( $_[1] ){ $t2_id = $_[1] } return $t2_id; } );
	$mock_target_2->mock('target_name', sub { return 'gfp' } );
	$mock_target_2->mock('assembly', sub { return undef } );
	$mock_target_2->mock('chr', sub { return undef } );
	$mock_target_2->mock('start', sub { return 1 } );
	$mock_target_2->mock('end', sub { return 720 } );
	$mock_target_2->mock('strand', sub { return '1' } );
	$mock_target_2->mock('species', sub { return undef } );
	$mock_target_2->mock('requires_enzyme', sub { return 'n' } );
	$mock_target_2->mock('gene_id', sub { return undef } );
	$mock_target_2->mock('gene_name', sub { return undef } );
	$mock_target_2->mock('requestor', sub { return 'crispr_test' } );
	$mock_target_2->mock('ensembl_version', sub { return undef } );
	$mock_target_2->mock('designed', sub { return undef } );

    # store - 1 test
    $target_adaptor->store($mock_target_2);
    $count++;
    is( $mock_target_2->target_id, 2, "$driver: Store target with undef attributes" );
    
    # fetch from db and check - 2 x 13 tests
    my $target_2;
    ( $target, $target_2 ) = @{ $target_adaptor->fetch_by_ids( [ 1, 2 ] ) };
    check_object_attributes( $target, $mock_target, $driver, 'fetch_by_ids 1' );
    check_object_attributes( $target_2, $mock_target_2, $driver, 'fetch_by_ids 2' );
    
    # drop database
    $db_connection->destroy();
}


sub check_object_attributes {
    my ( $obj_from_db, $obj, $driver, $method, ) = @_;
    is( $obj_from_db->target_id, $obj->target_id, "$driver: $method - Get id" );
    is( $obj_from_db->target_name, $obj->target_name, "$driver: $method - Get name" );
    is( $obj_from_db->chr, $obj->chr, "$driver: $method - Get chr" );
    is( $obj_from_db->start, $obj->start, "$driver: $method - Get start" );
    is( $obj_from_db->end, $obj->end, "$driver: $method - Get end" );
    is( $obj_from_db->strand, $obj->strand, "$driver: $method - Get strand" );
    is( $obj_from_db->species, $obj->species, "$driver: $method - Get species" );
    is( $obj_from_db->species, $obj->species, "$driver: $method - Get gene id" );
    is( $obj_from_db->gene_name, $obj->gene_name, "$driver: $method - Get gene name" );
    is( $obj_from_db->requestor, $obj_from_db->requestor, "$driver: $method - Get requestor" );
    is( $obj_from_db->ensembl_version, $obj->ensembl_version, "$driver: $method - Get version" );
    is( $obj_from_db->designed, $obj->designed, "$driver: $method - Get date" );
    isa_ok( $obj_from_db->target_adaptor, 'Crispr::DB::TargetAdaptor', "$driver: $method - check target adaptor");
}
