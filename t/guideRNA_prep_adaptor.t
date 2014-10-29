#!/usr/bin/env perl
# guideRNA_prep_adaptor.t
use warnings;
use strict;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Test::DatabaseRow;
use Data::Dumper;
use DateTime;
use Readonly;

use Crispr::DB::GuideRNAPrepAdaptor;
use Crispr::DB::DBConnection;

# Number of tests
Readonly my $TESTS_IN_COMMON => 1 + 16 + 7 + 2 + 3 + 7 + 8 + 14 + 8 + 32 + 1;
Readonly my %TESTS_FOREACH_DBC => (
    mysql => $TESTS_IN_COMMON,
    sqlite => $TESTS_IN_COMMON,
);
plan tests => $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite};

# check attributes and methods - 3 + 13 tests
my @attributes = ( qw{ dbname db_connection connection } );

my @methods = (
    qw{ store store_guideRNA_prep store_guideRNA_preps fetch_by_id fetch_by_ids
        fetch_all_by_crRNA_id fetch_all_by_injection_pool _fetch delete_guideRNA_prep_from_db check_entry_exists_in_db
        fetch_rows_expecting_single_row fetch_rows_for_generic_select_statement _db_error_handling }
);

# DB tests
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
my %test_db_connections;
foreach my $driver ( keys %db_connection_params ){
    $test_db_connections{$driver} = TestDB->new( $db_connection_params{$driver} );
}

# make a proper DB_Connection
my @db_connections;
foreach my $driver ( keys %db_connection_params ){
    push @db_connections, Crispr::DB::DBConnection->new( $db_connection_params{$driver} );
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
    
    ## make a mock DBConnection object
    #my $mock_db_connection = Test::MockObject->new();
    #$mock_db_connection->set_isa( 'Crispr::DB::DBConnection' );
    #$mock_db_connection->mock( 'dbname', sub { return $db_connection->dbname } );
    #$mock_db_connection->mock( 'connection', sub { return $db_connection->connection } );
    
    # add plate and crRNA info directly into the db
    my $plate_st = "insert into plate values ( ?, ?, ?, ?, ?, ? );";
    my $sth = $dbh->prepare($plate_st);
    $sth->execute( 1, 'CR_000001-', '96', 'crispr', undef, undef );
    $sth->execute( 2, 'CR_000001h', '96', 'guideRNA_prep', undef, undef );
    
    # target
    my $statement = "insert into target values( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'test_target', 'Zv9', '4', 1, 200, '1', 'zebrafish', 'y', 'GENE0001', 'gene001', 'crispr_test', 75, '2014-10-13');
    
    # crRNA
    $statement = "insert into crRNA values( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'crRNA:4:1-23:-1', '4', 1, 23, '-1', 'CACAGATGACAGATAGACAGCGG', 0, 0.81, 0.9, 0.9, 1, 1, 'A01' );
    $sth->execute( 2, 'crRNA:4:21-43:1', '4', 21, 43, '1', 'TAGATCAGTAGATCGATAGTAGG', 0, 0.81, 0.9, 0.9, 1, 1, 'B01' );

    # cas9 and injection pools
    $statement = "insert into cas9 values( ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'cas9_zf_dnls_native', 'pCS2_zf_dnls_Chen', 'some notes' );
    $statement = "insert into cas9_prep values( ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 1, 'rna', 'cr1', '2014-10-02' );
    $statement = "insert into injection values( ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, '170', 1, 200, '2014-10-02', 'H1435', 'MR1435', undef );
    
    # mock plate object
    my $mock_plate = Test::MockObject->new();
    $mock_plate->set_isa( 'Crispr::Plate' );
    $mock_plate->mock( 'plate_id', sub{ return 2 } );
    $mock_plate->mock( 'plate_name', sub{ return 'CR_000001h' } );
    $mock_plate->mock( 'plate_type', sub{ return '96' } );
    $mock_plate->mock( 'plate_category', sub{ return 'guideRNA_prep' } );
    $mock_plate->mock( 'ordered', sub{ return undef } );
    $mock_plate->mock( 'received', sub{ return undef } );
    
    my $mock_well = Test::MockObject->new();
    $mock_well->set_isa( 'Labware::Well' );
    $mock_well->mock( 'plate', sub{ return $mock_plate } );
    $mock_well->mock( 'plate_type', sub{ return '96' } );
    $mock_well->mock( 'position', sub{ return 'A01' } );
    
    my $mock_well_2 = Test::MockObject->new();
    $mock_well_2->set_isa( 'Labware::Well' );
    $mock_well_2->mock( 'plate', sub{ return $mock_plate } );
    $mock_well_2->mock( 'plate_type', sub{ return '96' } );
    $mock_well_2->mock( 'position', sub{ return 'A04' } );

    # mock crRNA objects
    my $mock_crRNA_object_1 = Test::MockObject->new();
    $mock_crRNA_object_1->set_isa( 'Crispr::crRNA' );
    $mock_crRNA_object_1->mock( 'crRNA_id', sub{ return 1 } );

    my $mock_crRNA_object_2 = Test::MockObject->new();
    $mock_crRNA_object_2->set_isa( 'Crispr::crRNA' );
    $mock_crRNA_object_2->mock( 'crRNA_id', sub{ return 2 } );
    
    # make mock GuidePrep objects
    my $mock_gRNA_1 = Test::MockObject->new();
    $mock_gRNA_1->set_isa( 'Crispr::DB::GuideRNAPrep' );
    my $g_id;
    $mock_gRNA_1->mock( 'db_id', sub{ my @args = @_; if( $_[1] ){ $g_id = $_[1] } return $g_id; } );
    $mock_gRNA_1->mock( 'type', sub{ return 'sgRNA' } );
    $mock_gRNA_1->mock( 'concentration', sub{ return 50 } );
    $mock_gRNA_1->mock( 'made_by', sub{ return 'cr1' } );
    $mock_gRNA_1->mock( 'date', sub{ return '2014-10-02' } );
    $mock_gRNA_1->mock( 'crRNA', sub{ return $mock_crRNA_object_1 } );
    $mock_gRNA_1->mock( 'crRNA_id', sub{ return $mock_crRNA_object_1->crRNA_id } );
    $mock_gRNA_1->mock( 'well', sub{ return $mock_well } );

    $mock_well->mock( 'contents', sub{ $mock_gRNA_1  } );
    
    my $mock_gRNA_2 = Test::MockObject->new();
    my $g2_id;
    $mock_gRNA_2->set_isa( 'Crispr::DB::GuideRNAPrep' );
    $mock_gRNA_2->mock( 'db_id', sub{ my @args = @_; if( $_[1] ){ $g2_id = $_[1] } return $g2_id; } );
    $mock_gRNA_2->mock( 'type', sub{ return 'sgRNA' } );
    $mock_gRNA_2->mock( 'concentration', sub{ return 60 } );
    $mock_gRNA_2->mock( 'made_by', sub{ return 'cr1' } );
    $mock_gRNA_2->mock( 'date', sub{ return '2014-10-02' } );
    $mock_gRNA_2->mock( 'crRNA', sub{ return $mock_crRNA_object_2 } );
    $mock_gRNA_2->mock( 'crRNA_id', sub{ return $mock_crRNA_object_2->crRNA_id } );
    $mock_gRNA_2->mock( 'well', sub{ return $mock_well_2 } );
    

    # make a new real GuideRNAPrep Adaptor
    my $guideRNA_prep_adaptor = Crispr::DB::GuideRNAPrepAdaptor->new( db_connection => $db_connection, );
    # 1 test
    isa_ok( $guideRNA_prep_adaptor, 'Crispr::DB::GuideRNAPrepAdaptor', "$driver: check object class is ok" );
    
    # check attributes and methods exist 3 + 13 tests
    foreach my $attribute ( @attributes ) {
        can_ok( $guideRNA_prep_adaptor, $attribute );
    }
    foreach my $method ( @methods ) {
        can_ok( $guideRNA_prep_adaptor, $method );
    }
    
    # check store methods 7 tests
    ok( $guideRNA_prep_adaptor->store( $mock_gRNA_1 ), "$driver: store" );
    row_ok(
       table => 'guideRNA_prep',
       where => [ guideRNA_prep_id => 1 ],
       tests => {
           'eq' => {
                guideRNA_type => $mock_gRNA_1->type,
                made_by  => $mock_gRNA_1->made_by,
                date  => $mock_gRNA_1->date,
                well_id => $mock_gRNA_1->well->position,
           },
           '==' => {
                crRNA_id => 1,
                concentration => $mock_gRNA_1->concentration,
                plate_id => $mock_gRNA_1->well->plate->plate_id,
           },
       },
       label => "$driver: guideRNA_prep stored",
    );

    # test that store throws properly
    throws_ok { $guideRNA_prep_adaptor->store_guideRNA_prep('GuideRNAPrep') }
        qr/Argument\smust\sbe\sCrispr::DB::GuideRNAPrep\sobject/,
        "$driver: store_guideRNA_prep throws on string input";
    throws_ok { $guideRNA_prep_adaptor->store_guideRNA_prep($mock_plate) }
        qr/Argument\smust\sbe\sCrispr::DB::GuideRNAPrep\sobject/,
        "$driver: store_guideRNA_prep throws if object is not Crispr::DB::GuideRNAPrep";
    my $regex = $driver eq 'mysql' ?   qr/Duplicate\sentry/xms
        :                           qr/PRIMARY\sKEY\smust\sbe\sunique/xms;
    
    throws_ok { $guideRNA_prep_adaptor->store_guideRNA_prep( $mock_gRNA_1 ) }
        $regex, "$driver: store_guideRNA_prep throws because of duplicate entry";

    $mock_well->mock( 'position', sub{ return 'A02' } );
    $g_id = 2;
    ok( $guideRNA_prep_adaptor->store_guideRNA_prep( $mock_gRNA_1 ), "$driver: store_guideRNA_prep" );
    row_ok(
       table => 'guideRNA_prep',
       where => [ guideRNA_prep_id => 2 ],
       tests => {
           'eq' => {
                guideRNA_type => $mock_gRNA_1->type,
                made_by  => $mock_gRNA_1->made_by,
                date  => $mock_gRNA_1->date,
                well_id => $mock_gRNA_1->well->position,
           },
           '==' => {
                crRNA_id => 1,
                concentration => $mock_gRNA_1->concentration,
                plate_id => $mock_gRNA_1->well->plate->plate_id,
           },
       },
       label => "$driver: guideRNA_prep pool stored",
    );

    # throws ok - 2 tests
    throws_ok { $guideRNA_prep_adaptor->store_guideRNA_preps('GuideRNAPrepObject') }
        qr/Supplied\sargument\smust\sbe\san\sArrayRef\sof\sGuideRNAPrep\sobjects/,
        "$driver: store_guideRNA_preps throws on non ARRAYREF";
    throws_ok { $guideRNA_prep_adaptor->store_guideRNA_preps( [ 'GuideRNAPrepObject' ] ) }
        qr/Argument\smust\sbe\sCrispr::DB::GuideRNAPrep\sobject/,
        "$driver: store_guideRNA_preps throws on string input";
    
    $mock_well->mock( 'position', sub{ return 'A03' } );
    $g_id = 3;
    # 3 tests
    ok( $guideRNA_prep_adaptor->store_guideRNA_preps( [ $mock_gRNA_1, $mock_gRNA_2 ] ), "$driver: store_guideRNA_preps" );
    row_ok(
       table => 'guideRNA_prep',
       where => [ guideRNA_prep_id => 3 ],
       tests => {
           'eq' => {
                guideRNA_type => $mock_gRNA_1->type,
                made_by  => $mock_gRNA_1->made_by,
                date  => $mock_gRNA_1->date,
                well_id => $mock_gRNA_1->well->position,
           },
           '==' => {
                crRNA_id => 1,
                concentration => $mock_gRNA_1->concentration,
                plate_id => $mock_gRNA_1->well->plate->plate_id,
           },
       },
       label => "$driver: guideRNA_preps stored",
    );
    row_ok(
       table => 'guideRNA_prep',
       where => [ guideRNA_prep_id => 4 ],
       tests => {
           'eq' => {
                guideRNA_type => $mock_gRNA_2->type,
                made_by  => $mock_gRNA_2->made_by,
                date  => $mock_gRNA_2->date,
                well_id => $mock_gRNA_2->well->position,
           },
           '==' => {
                crRNA_id => 2,
                concentration => $mock_gRNA_2->concentration,
                plate_id => $mock_gRNA_2->well->plate->plate_id,
           },
       },
       label => "$driver: guideRNA_preps stored",
    );
    
    
    # _fetch - 7 tests
    my $gRNA_prep_from_db = @{ $guideRNA_prep_adaptor->_fetch( 'guideRNA_prep_id = ?', [ 3, ] ) }[0];
    check_attributes( $gRNA_prep_from_db, $mock_gRNA_1, $driver, '_fetch', );
    
    # fetch_by_id - 8 tests
    $gRNA_prep_from_db = $guideRNA_prep_adaptor->fetch_by_id( 4 );
    check_attributes( $gRNA_prep_from_db, $mock_gRNA_2, $driver, 'fetch_by_id', );
    throws_ok{ $guideRNA_prep_adaptor->fetch_by_id( 10 ) } qr/Couldn't retrieve guideRNA_prep/, 'guideRNA_prep does not exist in db';
    
    # fetch_by_ids - 14 tests
    my @ids = ( 3, 4 );
    my $gRNA_preps_from_db = $guideRNA_prep_adaptor->fetch_by_ids( \@ids );
    
    my @guideRNA_preps = ( $mock_gRNA_1, $mock_gRNA_2 );
    foreach my $i ( 0..1 ){
        my $gRNA_prep_from_db = $gRNA_preps_from_db->[$i];
        my $mock_gRNA = $guideRNA_preps[$i];
        check_attributes( $gRNA_prep_from_db, $mock_gRNA, $driver, 'fetch_by_ids', );
    }

    # fetch by crRNA_id - 8 tests
    ok( $gRNA_preps_from_db = $guideRNA_prep_adaptor->fetch_all_by_crRNA_id( $mock_crRNA_object_2->crRNA_id ), 'fetch_all_by_crRNA_id');
    check_attributes( $gRNA_preps_from_db->[0], $mock_gRNA_2, $driver, 'fetch_all_by_crRNA_id', );

TODO: {
    local $TODO = 'methods not implemented yet.';
    
    # fetch_all_inj_pool 32 tests
    # add injection pool to db
    $statement = "insert into injection_pool values( ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 1, 3, 20, );
    $sth->execute( 1, 2, 4, 20, );
    my $mock_inj_pool = Test::MockObject->new();
    $mock_inj_pool->set_isa('Crispr::DB::InjectionPool');
    $mock_inj_pool->mock('db_id', sub { return 1 } );
    
    # use id
    ok( $gRNA_preps_from_db = $guideRNA_prep_adaptor->fetch_all_by_injection_pool( $mock_inj_pool ),
       'fetch guide RNA preps by InjPool (id)' );
    check_attributes( $gRNA_preps_from_db->[0], $mock_gRNA_1, $driver, 'fetch_all_by_injection_pool - 1', );
    check_attributes( $gRNA_preps_from_db->[1], $mock_gRNA_2, $driver, 'fetch_all_by_injection_pool - 1', );
    
    # use inj name
    $mock_inj_pool->mock('db_id', sub { return undef } );
    $mock_inj_pool->mock('pool_name', sub { return '170' } );
    ok( $gRNA_preps_from_db = $guideRNA_prep_adaptor->fetch_all_by_injection_pool( $mock_inj_pool ),
       'fetch guide RNA preps by InjPool (name)' );
    check_attributes( $gRNA_preps_from_db->[0], $mock_gRNA_1, $driver, 'fetch_all_by_injection_pool - 2', );
    check_attributes( $gRNA_preps_from_db->[1], $mock_gRNA_2, $driver, 'fetch_all_by_injection_pool - 2', );    
    
    # check throws ok
    throws_ok{ $guideRNA_prep_adaptor->fetch_all_by_injection_pool( 'InjectionPool' ) }
        qr/The\ssupplied\sobject\sshould\sbe\sa\sCrispr::DB::InjectionPool\sobject/,
        'check throws on string input';
    throws_ok{ $guideRNA_prep_adaptor->fetch_all_by_injection_pool( $mock_well ) }
        qr/The\ssupplied\sobject\sshould\sbe\sa\sCrispr::DB::InjectionPool\sobject/,
        'check throws on NON InjectionPool object';
    
    ok( $guideRNA_prep_adaptor->delete_guideRNA_prep_from_db ( 1 ), 'delete_guideRNA_prep_from_db');

}
    $test_db_connections{$driver}->destroy();
}

# 7 tests per call
sub check_attributes {
    my ( $object1, $object2, $driver, $method ) = @_;
    is( $object1->db_id, $object2->db_id, "$driver: object from db $method - check db_id");
    is( $object1->type, $object2->type, "$driver: object from db $method - check type");
    is( abs( $object1->concentration - $object2->concentration ) < 0.1, 1, "$driver: object from db $method - check concentration");
    is( $object1->made_by, $object2->made_by, "$driver: object from db $method - check made_by");
    is( $object1->date, $object2->date, "$driver: object from db $method - check date");

    is( $object1->crRNA->crRNA_id, $object2->crRNA->crRNA_id, "$driver: object from db $method - check crRNA_id");
    is( $object1->well->position, $object2->well->position, "$driver: object from db $method - check crRNA_id");
    
}

