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

my $test_data = 't/data/test_data_targets.txt';
my $count_output = qx/wc -l $test_data/;
chomp $count_output;
$count_output =~ s/\s$test_data//mxs;

# Number of tests
Readonly my $TESTS_IN_COMMON => 17 + 17 + ($count_output - 1)* 2;
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

    # check attributes and methods - 3 + 14 tests
    my @object_attributes = ( qw{ dbname db_connection connection } );
    
    my @methods = (
        qw{ store store_targets update_designed fetch_by_id fetch_by_ids
            fetch_by_name_and_requestor fetch_by_names_and_requestors fetch_by_crRNA _fetch delete_target_from_db
            check_entry_exists_in_db fetch_rows_expecting_single_row fetch_rows_for_generic_select_statement _db_error_handling }
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
    
    # store target
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
    
    # fetch target by name from database
    my $target_3 = $target_adaptor->fetch_by_name_and_requestor( 'SLC39A14', 'crispr_test' );
    #print Dumper( $target_3 );
    #exit;
    # 13 tests
    is( $target_3->target_id, $count, "$driver: Get id" );
    is( $target_3->target_name, 'SLC39A14', "$driver: Get name" );
    is( $target_3->chr, '5', "$driver: Get chr" );
    is( $target_3->start, 18067321, "$driver: Get start" );
    is( $target_3->end, 18083466, "$driver: Get end" );
    is( $target_3->strand, '-1', "$driver: Get strand" );
    is( $target_3->species, 'danio_rerio', "$driver: Get species" );
    is( $target_3->gene_id , 'ENSDARG00000090174', "$driver: Get gene id" );
    is( $target_3->gene_name , 'SLC39A14', "$driver: Get gene name" );
    is( $target_3->requestor , 'crispr_test', "$driver: Get requestor" );
    is( $target_3->ensembl_version , 71, "$driver: Get version" );
    is( $target_3->designed, undef, "$driver: Get date" );
    isa_ok( $target_3->target_adaptor, 'Crispr::DB::TargetAdaptor', "$driver: check target adaptor");
    
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

    # store - 2 tests
    $target_adaptor->store($mock_target_2);
    $count++;
    is( $mock_target_2->target_id, 2, "$driver: Store target with undef attributes" );
    
    open my $fh, '<', $test_data or die "Couldn't open file: $test_data!\n";
    my %target_seen;
    
    # 2 tests per target
	my @values;
    while(<$fh>){
        chomp;
        if( m/\A $comment_regex/xms ){
            s|$comment_regex||xms;
            @columns = split /\t/, $_;
            foreach my $column_name ( @columns ){
                if( !any { $column_name eq $_ } @attributes ){
                    die "Could not recognise column name, ", $column_name, ".\n";
                }
            }
            foreach my $attribute ( @required_attributes ){
                if( !any { $attribute eq $_ } @columns ){
                    die "Missing required attribute: ", $attribute, ".\n";
                    }
            }
            next;
        }
        else{
            @values = split /\t/, $_;
        }
        die "Could not find header\n" if( !@columns );
        
        my %args;
        for( my $i = 0; $i < scalar @columns; $i++ ){
            if( $values[$i] eq 'NULL' ){
                $values[$i] = undef;
            }
            $args{ $columns[$i] } = $values[$i];
        }
        
        next if( exists $target_seen{ $args{'target_name'} } );
        $target_seen{ $args{'target_name'} } = 1; 
        
        my $mock_target = Test::MockObject->new();
        $mock_target->set_isa( 'Crispr::Target' );
        my $t_id;
        $mock_target->mock( 'target_id', sub{ my @args = @_; if( $_[1] ){ $t_id = $_[1] } return $t_id; } );
        $mock_target->mock( 'target_name', sub { return $args{ 'target_name' } } );
        $mock_target->mock( 'assembly', sub { return $args{ 'assembly' } } );
        $mock_target->mock( 'chr', sub { return $args{ 'chr' } } );
        $mock_target->mock( 'start', sub { return $args{ 'start' } } );
        $mock_target->mock( 'end', sub { return $args{ 'end' } } );
        $mock_target->mock( 'strand', sub { return $args{ 'strand' } } );
        $mock_target->mock( 'species', sub { return $args{ 'species' } } );
        $mock_target->mock( 'requires_enzyme', sub { return $args{ 'requires_enzyme' } } );
        $mock_target->mock( 'gene_id', sub { return $args{ 'gene_id' } } );
        $mock_target->mock( 'gene_name', sub { return $args{ 'gene_name' } } );
        $mock_target->mock( 'requestor', sub { return $args{ 'requestor' } } );
        $mock_target->mock( 'ensembl_version', sub { return $args{ 'ensembl_version' } } );
        $mock_target->mock( 'designed', sub { return $args{ 'designed' } } );
        
        $target_adaptor->store($mock_target);
        $count++;
        is( $mock_target->target_id, $count, "$driver: Target id - $args{target_name}");
        row_ok(
           table => 'target',
           where => [ target_id => $count ],
           tests => {
               'eq' => {
                    target_name => $mock_target->target_name,
                    assembly => $mock_target->assembly,
                    chr  => $mock_target->chr,
                    strand => $mock_target->strand,
                    species => $mock_target->species,
                    requires_enzyme => $mock_target->requires_enzyme,
                    gene_id => $mock_target->gene_id,
                    gene_name => $mock_target->gene_name,
                    requestor => $mock_target->requestor,
                    designed => undef,
               },
               '==' => {
                    start  => $mock_target->start,
                    end    => $mock_target->end,
                    ensembl_version => $mock_target->ensembl_version,
               },
           },
           label => "$driver: Target stored - $args{target_name}",
        );
    
    }
    close($fh);
    
    # drop database
    $db_connection->destroy();
}

