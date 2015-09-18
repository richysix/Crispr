#!/usr/bin/env perl
# crispr_pair_adaptor.t
use strict; use warnings;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use Test::DatabaseRow;
use Readonly;
use File::Spec;
use English qw( -no_match_vars );

use Crispr::DB::DBConnection;
#use Crispr::CrisprPair;
use Crispr::DB::CrisprPairAdaptor;

Readonly my $TESTS_IN_COMMON => 1 + 6 + 3 + 18 + 8;
Readonly my %TESTS_FOREACH_DBC => (
    mysql => $TESTS_IN_COMMON,
    sqlite => $TESTS_IN_COMMON,
);
if( $ENV{NO_DB} ) {
    plan skip_all => 'Not testing database';
}
else {
    plan tests => $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite};
}

##  database tests  ##
# Module with a function for creating an empty test database
# and returning a database connection
use lib 't/lib';
use TestDB;

my %db_connection_params = (
    mysql => {
        driver => 'mysql',
        dbname => $ENV{MYSQL_DBNAME},
        host => $ENV{MYSQL_DBHOST},
        port => $ENV{MYSQL_DBPORT},
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
foreach my $driver ( 'mysql', 'sqlite' ){
    my $adaptor;
    eval {
        $adaptor = TestDB->new( $driver );
    };
    if( $EVAL_ERROR ){
        if( $EVAL_ERROR =~ m/ENVIRONMENT VARIABLES/ ){
            warn "The following environment variables need to be set for testing connections to a MySQL database!\n",
                    q{$MYSQL_DBNAME, $MYSQL_DBHOST, $MYSQL_DBPORT, $MYSQL_DBUSER, $MYSQL_DBPASS}, "\n";
        }
    }
    if( defined $adaptor ){
        # reconnect to db using DBConnection
        push @db_connections, $adaptor;
    }
}

SKIP: {
    skip 'No database connections available', $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite} if !@db_connections;
    
    if( @db_connections == 1 ){
        skip 'Only one database connection available', $TESTS_FOREACH_DBC{sqlite} if $db_connections[0]->driver eq 'mysql';
        skip 'Only one database connection available', $TESTS_FOREACH_DBC{mysql} if $db_connections[0]->driver eq 'sqlite';
    }
}

foreach my $db_connection ( @db_connections ){
    my $driver = $db_connection->driver;
    my $dbh = $db_connection->connection->dbh;

    # $dbh is a DBI database handle
    local $Test::DatabaseRow::dbh = $dbh;
    
    # make a real DBConnection object
    my $db_conn = Crispr::DB::DBConnection->new( $db_connection_params{$driver} );
    # make a new real CrisprPair Adaptor
    my $crispr_pair_ad = Crispr::DB::CrisprPairAdaptor->new( db_connection => $db_conn, );
    # 1 test
    isa_ok( $crispr_pair_ad, 'Crispr::DB::CrisprPairAdaptor' );
    
    # test methods - 6 tests
    my @methods = qw( db_connection crRNA_adaptor store_crispr_pair
        store store_crispr_pairs _build_crRNA_adaptor
    );
    
    foreach my $method ( @methods ) {
        can_ok( $crispr_pair_ad, $method );
    }
    
    # make mock objects
    # TARGET
    my $mock_target = Test::MockObject->new();
    $mock_target->set_isa('Crispr::Target');
    $mock_target->mock('target_name', sub{ 'target_name' } );
    $mock_target->mock('assembly', sub{ 'Zv9' } );
    $mock_target->mock('chr', sub{ '5' } );
    $mock_target->mock('start', sub{ '50000' } );
    $mock_target->mock('end', sub{ '50500' } );
    $mock_target->mock('strand', sub{ '1' } );
    $mock_target->mock('species', sub{ 'zebrafish' } );
    $mock_target->mock('requires_enzyme', sub{ 'n' } );
    $mock_target->mock('gene_id', sub{ 'ENSDARG0100101' } );
    $mock_target->mock('gene_name', sub{ 'gene_name' } );
    $mock_target->mock('requestor', sub{ 'crispr_test' } );
    $mock_target->mock('ensembl_version', sub{ '71' } );
    $mock_target->mock('designed', sub{ '2013-08-09' } );
    $mock_target->mock('target_id', sub{ '1' } );
    $mock_target->mock('info', sub{ return ( qw{ 1 name Zv9 5 50000 50500 1
        zebrafish n  ENSDARG0100101 gene_name crispr_test 71 2013-08-09 } ) } );
    
    # crRNAs
    my $mock_crRNA_1 = Test::MockObject->new();
    $mock_crRNA_1->set_isa('Crispr::crRNA');
    $mock_crRNA_1->mock('crRNA_id', sub{ '1' } );
    $mock_crRNA_1->mock('name', sub{ 'crRNA:5:50383-50405:-1' } );
    $mock_crRNA_1->mock('chr', sub{ '5' } );
    $mock_crRNA_1->mock('start', sub{ '50383' } );
    $mock_crRNA_1->mock('end', sub{ '50405' } );
    $mock_crRNA_1->mock('strand', sub{ '-1' } );
    $mock_crRNA_1->mock('cut_site', sub{ '50388' } );
    $mock_crRNA_1->mock('sequence', sub{ 'GGAATAGAGAGATAGAGAGTCGG' } );
    $mock_crRNA_1->mock('forward_oligo', sub{ 'ATGGGGAATAGAGAGATAGAGAGT' } );
    $mock_crRNA_1->mock('reverse_oligo', sub{ 'AAACACTCTCTATCTCTCTATTCC' } );
    $mock_crRNA_1->mock('score', sub{ '0.853' } );
    $mock_crRNA_1->mock('coding_score', sub{ '0.853' } );
    $mock_crRNA_1->mock('off_target_score', sub{ '0.95' } );
    $mock_crRNA_1->mock('target_id', sub{ '1' } );
    $mock_crRNA_1->mock('target', sub{ return $mock_target } );
    $mock_crRNA_1->mock('unique_restriction_sites', sub { return undef } );
    $mock_crRNA_1->mock('coding_scores', sub { return undef } );
    $mock_crRNA_1->mock( 'off_target_hits', sub { return undef } );
    $mock_crRNA_1->mock( 'plasmid_backbone', sub { return 'pDR274' } );
    $mock_crRNA_1->mock( 'primer_pairs', sub { return undef } );
    $mock_crRNA_1->mock( 'info', sub { return ( qw{ crRNA:5:50383-50405:-1 5 50383
        50405 -1 0.853 GGAATAGAGAGATAGAGAGTCGG ATGGGGAATAGAGAGATAGAGAGT
        AAACACTCTCTATCTCTCTATTCC NULL NULL NULL NULL NULL NULL NULL 2 pDR274 } ); });
    $mock_crRNA_1->mock( 'five_prime_Gs', sub { return 0 } );
    
    my $mock_crRNA_2 = Test::MockObject->new();
    $mock_crRNA_2->set_isa('Crispr::crRNA');
    $mock_crRNA_2->mock('crRNA_id', sub{ '2' } );
    $mock_crRNA_2->mock('name', sub{ 'crRNA:5:50403-50425:1' } );
    $mock_crRNA_2->mock('chr', sub{ '5' } );
    $mock_crRNA_2->mock('start', sub{ '50403' } );
    $mock_crRNA_2->mock('end', sub{ '50425' } );
    $mock_crRNA_2->mock('strand', sub{ '1' } );
    $mock_crRNA_2->mock('cut_site', sub{ '50419' } );
    $mock_crRNA_2->mock('sequence', sub{ 'GGAATAGAGAGATAGAGAGTCGG' } );
    $mock_crRNA_2->mock('forward_oligo', sub{ 'ATGGGGAATAGAGAGATAGAGAGT' } );
    $mock_crRNA_2->mock('reverse_oligo', sub{ 'AAACACTCTCTATCTCTCTATTCC' } );
    $mock_crRNA_2->mock('score', sub{ '0.853' } );
    $mock_crRNA_2->mock('coding_score', sub{ '0.853' } );
    $mock_crRNA_2->mock('off_target_score', sub{ '0.90' } );
    $mock_crRNA_2->mock('target_id', sub{ '1' } );
    $mock_crRNA_2->mock('target', sub{ return $mock_target } );
    $mock_crRNA_2->mock('unique_restriction_sites', sub { return undef } );
    $mock_crRNA_2->mock('coding_scores', sub { return undef } );
    $mock_crRNA_2->mock( 'off_target_hits', sub { return undef } );
    $mock_crRNA_2->mock( 'plasmid_backbone', sub { return 'pDR274' } );
    $mock_crRNA_2->mock( 'primer_pairs', sub { return undef } );
    $mock_crRNA_2->mock( 'info', sub { return ( qw{ crRNA:5:50403-50425:-1 5 50403
        50425 1 0.853 GGAATAGAGAGATAGAGAGTCGG ATGGGGAATAGAGAGATAGAGAGT
        AAACACTCTCTATCTCTCTATTCC NULL NULL NULL NULL NULL NULL NULL 2 pDR274 } ); });
    $mock_crRNA_2->mock( 'five_prime_Gs', sub { return 0 } );
    
    my $p_id = undef;
    my $mock_crispr_pair = Test::MockObject->new();
    $mock_crispr_pair->set_isa('Crispr::CrisprPair');
    $mock_crispr_pair->mock('pair_id', sub { return $p_id } );
    $mock_crispr_pair->mock('target_name', sub { return 'test_target' } );
    $mock_crispr_pair->mock('target_1', sub { return $mock_target } );
    $mock_crispr_pair->mock('target_2', sub { return $mock_target } );
    $mock_crispr_pair->mock('crRNA_1', sub { return $mock_crRNA_1 } );
    $mock_crispr_pair->mock('crRNA_2', sub { return $mock_crRNA_2 } );
    $mock_crispr_pair->mock('paired_off_targets', sub { return 0 } );
    $mock_crispr_pair->mock('overhang_top', sub { return 'GATAGATAGCGATAGACAG' } );
    $mock_crispr_pair->mock('overhang_bottom', sub { return 'GACTACGATGAAGATACGA' } );
    $mock_crispr_pair->mock('crRNAs', sub { return [ $mock_crRNA_1, $mock_crRNA_2 ] } );
    $mock_crispr_pair->mock('_set_pair_id', sub { $p_id = $_[1];  } );
    
    # check store method - 3 tests
    is( $crispr_pair_ad->store_crispr_pair( $mock_crispr_pair ), 1, "$driver: store a single crispr pair" );
    
    # check rows
    my %row;
    row_ok(
        sql => "SELECT * FROM crRNA_pair WHERE crRNA_pair_id = 1;",
        store_row => \%row,
        tests => {
            '==' => {
                 crRNA_1_id  => 1,
                 crRNA_2_id  => 2,
            },
        },
        label => "$driver: check db row",
    );
    
    # check crRNA rows as well
    my @rows;
    row_ok(
        sql => "SELECT * FROM crRNA;",
        store_rows => \@rows,
    );
    
    # 18 tests
    foreach my $row ( @rows ){
        is( $row->{chr}, '5', "$driver: crRNA chr from db" );
        is( $row->{score}, 0.853, "$driver: crRNA score from db" );
        is( $row->{coding_score}, 0.853, "$driver: crRNA coding score from db" );
        is( $row->{target_id}, 1, "$driver: crRNA chr from db" );
        is( $row->{sequence}, 'GGAATAGAGAGATAGAGAGTCGG', "$driver: crRNA seq from db" );
        if( $row->{crRNA_name} eq 'crRNA:5:50383-50405:-1' ){
            is( $row->{ crRNA_id }, 1, "$driver: crRNA_1 id from db" );
            is( $row->{ start }, $mock_crRNA_1->start, "$driver: crRNA_1 start from db");
            is( $row->{ end }, $mock_crRNA_1->end, "$driver: crRNA_1 end from db");
            is( $row->{ strand }, $mock_crRNA_1->strand, "$driver: crRNA_1 strand from db");
        }
        elsif( $row->{crRNA_name} eq 'crRNA:5:50403-50425:1' ){
            is( $row->{ crRNA_id }, 2, "$driver: crRNA_2 id from db" );
            is( $row->{ start }, $mock_crRNA_2->start, "$driver: crRNA_2 start from db");
            is( $row->{ end }, $mock_crRNA_2->end, "$driver: crRNA_2 end from db");
            is( $row->{ strand }, $mock_crRNA_2->strand, "$driver: crRNA_2 strand from db");
        }
        else{
            die "Row isn't expected!\n";
        }
    }
    
    # check store methods throw properly - 8 tests
    my $error_message = 'Arguments must all be Crispr::CrisprPair objects';
    throws_ok { $crispr_pair_ad->store( 'This is not a crispr pair' ) } qr/$error_message/, 'Non CrisprPair argument to store';
    throws_ok { $crispr_pair_ad->store_crispr_pair( 'This is not a crispr pair' ) } qr/$error_message/, 'Non CrisprPair argument to store_crispr_pair';
    throws_ok { $crispr_pair_ad->store_crispr_pairs( [ 'This is not a crispr pair' ] ) } qr/$error_message/, 'Non CrisprPair argument to store_crispr_pairs';
    
    $error_message = 'At least one Crispr Pair must be supplied';
    throws_ok { $crispr_pair_ad->store_crispr_pairs() } qr/$error_message/, 'undef argument to store_crispr_pairs';
    
    $error_message = 'Crispr Pairs must be supplied as an ArrayRef!';
    throws_ok { $crispr_pair_ad->store_crispr_pairs( {} ) } qr/$error_message/, 'Non-ArrayRef argument to store_crispr_pairs';
    
    my $mock_crispr_pair_2 = Test::MockObject->new();
    $mock_crispr_pair_2->set_isa('Crispr::CrisprPair');
    $mock_crispr_pair_2->mock('pair_id', sub { return undef } );
    $mock_crispr_pair_2->mock('crRNA_1', sub { return undef } );
    
    $error_message = 'At least one of the crRNAs is not defined!';
    throws_ok { $crispr_pair_ad->store_crispr_pair( $mock_crispr_pair_2 ) } qr/$error_message/, 'undefined crRNAs';
    $mock_crispr_pair_2->mock('crRNA_1', sub { return $mock_crRNA_1 } );
    $mock_crispr_pair_2->mock('crRNA_2', sub { return undef } );
    
    $error_message = 'At least one of the crRNAs is not defined!';
    throws_ok { $crispr_pair_ad->store_crispr_pair( $mock_crispr_pair_2 ) } qr/$error_message/, 'undefined crRNAs';
    $mock_crispr_pair_2->mock('crRNA_1', sub { return undef } );
    $mock_crispr_pair_2->mock('crRNA_2', sub { return $mock_crRNA_2 } );
    
    $error_message = 'At least one of the crRNAs is not defined!';
    throws_ok { $crispr_pair_ad->store_crispr_pair( $mock_crispr_pair_2 ) } qr/$error_message/, 'undefined crRNAs';
    
    # destroy database
    $db_connection->destroy();    
}

