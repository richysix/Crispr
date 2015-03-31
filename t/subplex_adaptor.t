#!/usr/bin/env perl
# subplex_adaptor.t
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

use Crispr::DB::SubplexAdaptor;
use Crispr::DB::DBConnection;

# Number of tests
Readonly my $TESTS_IN_COMMON => 1 + 20 + 4 + 5 + 4 + 3 + 1;
#Readonly my $TESTS_IN_COMMON => 1 + 20 + 4 + 13 + 2 + 3 + 24 + 24 + 48 + 25 + 2;
Readonly my %TESTS_FOREACH_DBC => (
    mysql => $TESTS_IN_COMMON,
    sqlite => $TESTS_IN_COMMON,
);
plan tests => $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite};

# check attributes and methods - 5 + 15 tests
my @attributes = ( qw{ dbname db_connection connection plex_adaptor injection_pool_adaptor } );

my @methods = (
    qw{ store store_subplex store_subplexes fetch_by_id fetch_by_ids
        fetch_all_by_plex_id fetch_all_by_plex fetch_all_by_injection_id fetch_all_by_injection_pool _fetch
        delete_subplex_from_db check_entry_exists_in_db fetch_rows_expecting_single_row fetch_rows_for_generic_select_statement _db_error_handling }
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
    
    # make mock Plex and InjectionPool objects
    my $mock_plex = Test::MockObject->new();
    $mock_plex->set_isa( 'Crispr::DB::Plex' );
    my $p_id = 1;
    my $plex_name = 'MPX14';
    $mock_plex->mock( 'db_id', sub{ my @args = @_; if( $_[1] ){ $p_id = $_[1] } return $p_id; } );
    $mock_plex->mock( 'plex_name', sub{ return lc( $plex_name ) } );
    $mock_plex->mock( 'run_id', sub{ return 13831 } );
    $mock_plex->mock( 'analysis_started', sub{ return '2014-09-27' } );
    $mock_plex->mock( 'analysis_finished', sub{ return undef } );

    # insert directly into db
    my $statement = "insert into plex values( ?, ?, ?, ?, ? );";
    my $sth = $dbh->prepare($statement);
    $sth->execute( $mock_plex->db_id,
        $mock_plex->plex_name,
        $mock_plex->run_id,
        $mock_plex->analysis_started,
        $mock_plex->analysis_finished,
        );
    
    # make mock InjectionPool
    # needs cas9, cas9prep, crRNAs and gRNAs
    # make mock Cas9 and Cas9Prep objects
    my $type = 'ZfnCas9n';
    my $vector = 'pCS2';
    my $name = join(q{-}, $vector, $type, );
    my $species = 's_pyogenes';
    my $target_seq = 'NNNNNNNNNNNNNNNNNN';
    my $pam = 'NGG';
    my $crispr_target_seq = $target_seq . $pam;
    my $mock_cas9_object = Test::MockObject->new();
    $mock_cas9_object->set_isa( 'Crispr::Cas9' );
    $mock_cas9_object->mock( 'db_id', sub{ return 1 } );
    $mock_cas9_object->mock( 'type', sub{ return $type } );
    $mock_cas9_object->mock( 'species', sub{ return $species } );
    $mock_cas9_object->mock( 'target_seq', sub{ return $target_seq } );
    $mock_cas9_object->mock( 'PAM', sub{ return $pam } );
    $mock_cas9_object->mock( 'name', sub{ return $name } );
    $mock_cas9_object->mock( 'vector', sub{ return $vector } );
    $mock_cas9_object->mock( 'species', sub{ return $species } );
    $mock_cas9_object->mock( 'crispr_target_seq', sub{ return $crispr_target_seq } );
    $mock_cas9_object->mock( 'info', sub{ return ( $type, $species, $crispr_target_seq ) } );
    # insert directly into db
    $statement = "insert into cas9 values( ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( $mock_cas9_object->db_id,
        $mock_cas9_object->name,
        $mock_cas9_object->type,
        $mock_cas9_object->vector,
        $mock_cas9_object->species,
        );
    
    my $prep_type = 'rna';
    my $made_by = 'cr_test';
    my $todays_date_obj = DateTime->now();
    my $mock_cas9_prep_object_1 = Test::MockObject->new();
    $mock_cas9_prep_object_1->set_isa( 'Crispr::DB::Cas9Prep' );
    $mock_cas9_prep_object_1->mock( 'db_id', sub{ return 1 } );
    $mock_cas9_prep_object_1->mock( 'cas9', sub{ return $mock_cas9_object } );
    $mock_cas9_prep_object_1->mock( 'prep_type', sub{ return $prep_type } );
    $mock_cas9_prep_object_1->mock( 'made_by', sub{ return $made_by } );
    $mock_cas9_prep_object_1->mock( 'date', sub{ return $todays_date_obj->ymd } );
    $mock_cas9_prep_object_1->mock( 'type', sub{ return $mock_cas9_object->type } );
    $mock_cas9_prep_object_1->mock( 'notes', sub{ return 'some notes' } );
    $mock_cas9_prep_object_1->mock('concentration', sub { return 200 } );
    # insert directly into db
    $statement = "insert into cas9_prep values( ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( $mock_cas9_prep_object_1->db_id, $mock_cas9_object->db_id,
        $mock_cas9_prep_object_1->prep_type, $mock_cas9_prep_object_1->made_by,
        $mock_cas9_prep_object_1->date, $mock_cas9_prep_object_1->notes  );
    
    my $mock_crRNA_object_1 = Test::MockObject->new();
    $mock_crRNA_object_1->set_isa( 'Crispr::crRNA' );
    $mock_crRNA_object_1->mock( 'crRNA_id', sub{ return 1 } );

    my $mock_crRNA_object_2 = Test::MockObject->new();
    $mock_crRNA_object_2->set_isa( 'Crispr::crRNA' );
    $mock_crRNA_object_2->mock( 'crRNA_id', sub{ return 2 } );
    
    my $mock_well = Test::MockObject->new();
    $mock_well->set_isa( 'Labware::Well' );
    #$mock_well->mock( 'plate', sub{ return $mock_plate } );
    #$mock_well->mock( 'plate_type', sub{ return '96' } );
    $mock_well->mock( 'position', sub{ return 'A01' } );
    
    my $mock_gRNA_1 = Test::MockObject->new();
    $mock_gRNA_1->set_isa( 'Crispr::guideRNA_prep' );
    $mock_gRNA_1->mock( 'db_id', sub{ return 1 } );
    $mock_gRNA_1->mock( 'type', sub{ return 'sgRNA' } );
    $mock_gRNA_1->mock( 'stock_concentration', sub{ return 50 } );
    $mock_gRNA_1->mock( 'injection_concentration', sub{ return 10 } );
    $mock_gRNA_1->mock( 'made_by', sub{ return 'cr1' } );
    $mock_gRNA_1->mock( 'date', sub{ return '2014-10-02' } );
    $mock_gRNA_1->mock( 'crRNA', sub{ return $mock_crRNA_object_1 } );
    $mock_gRNA_1->mock( 'crRNA_id', sub{ return $mock_crRNA_object_1->crRNA_id } );
    $mock_gRNA_1->mock( 'well', sub{ return $mock_well } );
    
    my $mock_well_2 = Test::MockObject->new();
    $mock_well_2->set_isa( 'Labware::Well' );
    #$mock_well_2->mock( 'plate', sub{ return $mock_plate } );
    #$mock_well_2->mock( 'plate_type', sub{ return '96' } );
    $mock_well_2->mock( 'position', sub{ return 'B01' } );
    
    my $mock_gRNA_2 = Test::MockObject->new();
    $mock_gRNA_2->set_isa( 'Crispr::guideRNA_prep' );
    $mock_gRNA_2->mock( 'db_id', sub{ return 2 } );
    $mock_gRNA_2->mock( 'type', sub{ return 'sgRNA' } );
    $mock_gRNA_2->mock( 'stock_concentration', sub{ return 60 } );
    $mock_gRNA_2->mock( 'injection_concentration', sub{ return 10 } );
    $mock_gRNA_2->mock( 'made_by', sub{ return 'cr1' } );
    $mock_gRNA_2->mock( 'date', sub{ return '2014-10-02' } );
    $mock_gRNA_2->mock( 'crRNA', sub{ return $mock_crRNA_object_2 } );
    $mock_gRNA_2->mock( 'crRNA_id', sub{ return $mock_crRNA_object_2->crRNA_id } );
    $mock_gRNA_2->mock( 'well', sub{ return $mock_well_2 } );
    
    # target
    $statement = "insert into target values( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'test_target', 'Zv9', '4', 1, 200, '1', 'zebrafish', 'y', 'GENE0001', 'gene001', 'crispr_test', 75, '2014-10-13');
    # plate 
    $statement = "insert into plate values( ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'CR_000001-', '96', 'crispr', undef, undef, );
    $sth->execute( 2, 'CR_000001h', '96', 'guideRNA_prep', undef, undef, );

    # crRNA
    $statement = "insert into crRNA values( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'crRNA:4:1-23:-1', '4', 1, 23, '-1', 'CACAGATGACAGATAGACAGCGG', 0, 0.81, 0.9, 0.9, 1, 1, 'A01' );
    $sth->execute( 2, 'crRNA:4:21-43:1', '4', 21, 43, '1', 'TAGATCAGTAGATCGATAGTAGG', 0, 0.81, 0.9, 0.9, 1, 1, 'B01' );
    # guideRNA
    $statement = "insert into guideRNA_prep values( ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 1, 'sgRNA', 50, 'cr1', '2014-10-02', 2, 'A01' );
    $sth->execute( 2, 1, 'sgRNA', 60, 'cr1', '2014-10-02', 2, 'B01' );

    my $mock_injection_pool = Test::MockObject->new();
    $mock_injection_pool->set_isa( 'Crispr::DB::InjectionPool' );
    my $i_id = 1;
    $mock_injection_pool->mock( 'db_id', sub{ my @args = @_; if( $_[1] ){ $i_id = $_[1] } return $i_id; } );
    $mock_injection_pool->mock( 'pool_name', sub{ return '170' } );
    $mock_injection_pool->mock( 'cas9_prep', sub{ return $mock_cas9_prep_object_1 } );
    $mock_injection_pool->mock( 'cas9_conc', sub{ return 200 } );
    $mock_injection_pool->mock( 'date', sub{ return '2014-10-13' } );
    $mock_injection_pool->mock( 'line_injected', sub{ return 'H1530' } );
    $mock_injection_pool->mock( 'line_raised', sub{ return undef } );
    $mock_injection_pool->mock( 'sorted_by', sub{ return 'cr_1' } );
    $mock_injection_pool->mock( 'guideRNAs', sub{ return [ $mock_gRNA_1, $mock_gRNA_2, ] } );
    # add directly to db
    $statement = "insert into injection values( ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute(
        $mock_injection_pool->db_id,
        $mock_injection_pool->pool_name,
        $mock_cas9_prep_object_1->db_id,
        $mock_cas9_prep_object_1->concentration,
        $mock_injection_pool->date,
        $mock_injection_pool->line_injected,
        $mock_injection_pool->line_raised,
        $mock_injection_pool->sorted_by,
    );
    $statement = "insert into injection_pool values( ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute(
        $mock_injection_pool->db_id,
        $mock_crRNA_object_1->crRNA_id,
        $mock_gRNA_1->db_id,
        $mock_gRNA_1->injection_concentration,
    );
    
    my $mock_subplex = Test::MockObject->new();
    $mock_subplex->set_isa( 'Crispr::DB::Subplex' );
    my $subplex_id;
    $mock_subplex->mock( 'db_id', sub{ my @args = @_; if( $_[1] ){ $subplex_id = $_[1] } return $subplex_id; } );
    $mock_subplex->mock( 'plex', sub{ return $mock_plex } );
    $mock_subplex->mock( 'injection_pool', sub{ return $mock_injection_pool } );
    $mock_subplex->mock( 'plate_num', sub{ return 1 } );
    
    # make a new real Subplex Adaptor
    my $subplex_adaptor = Crispr::DB::SubplexAdaptor->new( db_connection => $db_connection, );
    # 1 test
    isa_ok( $subplex_adaptor, 'Crispr::DB::SubplexAdaptor', "$driver: check object class is ok" );
    
    # check attributes and methods exist 5 + 15 tests
    foreach my $attribute ( @attributes ) {
        can_ok( $subplex_adaptor, $attribute );
    }
    foreach my $method ( @methods ) {
        can_ok( $subplex_adaptor, $method );
    }
    
    # check db adaptor attributes - 4 tests
    my $plex_adaptor;
    ok( $plex_adaptor = $subplex_adaptor->plex_adaptor(), "$driver: get plex_adaptor" );
    isa_ok( $plex_adaptor, 'Crispr::DB::PlexAdaptor', "$driver: check plex_adaptor class" );
    my $injection_pool_adaptor;
    ok( $injection_pool_adaptor = $subplex_adaptor->injection_pool_adaptor(), "$driver: get injection_pool_adaptor" );
    isa_ok( $injection_pool_adaptor, 'Crispr::DB::InjectionPoolAdaptor', "$driver: check injection_pool_adaptor class" );
    
    # check store methods 12 tests
    ok( $subplex_adaptor->store( $mock_subplex ), "$driver: store" );
    row_ok(
       table => 'subplex',
       where => [ subplex_id => 1 ],
       tests => {
           '==' => {
                plex_id => $mock_subplex->plex->db_id,
                plate_num => $mock_subplex->plate_num,
                injection_id => $mock_subplex->injection_pool->db_id,
           },
       },
       label => "$driver: subplex stored",
    );
    # test that store throws properly
    throws_ok { $subplex_adaptor->store_subplex('Subplex') }
        qr/Argument\smust\sbe\sCrispr::DB::Subplex\sobject/,
        "$driver: store_subplex throws on string input";
    throws_ok { $subplex_adaptor->store_subplex($mock_cas9_object) }
        qr/Argument\smust\sbe\sCrispr::DB::Subplex\sobject/,
        "$driver: store_subplex throws if object is not Crispr::DB::Subplex";
    
    # check throws ok on attempted duplicate entry
    # for this we need to suppress the warning that is generated as well, hence the nested warning_like test
    # This does not affect the apparent number of tests run
    my $regex = $driver eq 'mysql' ?   qr/Duplicate\sentry/xms
        :                           qr/PRIMARY\sKEY\smust\sbe\sunique/xms;
    
    throws_ok {
        warning_like { $subplex_adaptor->store_subplex( $mock_subplex ) }
            $regex;
    }
        $regex,
        "$driver: store_subplex throws because of duplicate entry";
    
    # store subplex - 4 tests
    $subplex_id = 2;
    ok( $subplex_adaptor->store_subplex( $mock_subplex ), "$driver: store_subplex" );
    row_ok(
       table => 'subplex',
       where => [ subplex_id => 2 ],
       tests => {
           '==' => {
                plex_id => $mock_subplex->plex->db_id,
                plate_num => $mock_subplex->plate_num,
                injection_id => $mock_subplex->injection_pool->db_id,
           },
       },
       label => "$driver: subplex stored",
    );
    
    throws_ok { $subplex_adaptor->store_subplexes('SubplexObject') }
        qr/Supplied\sargument\smust\sbe\san\sArrayRef\sof\sSubplex\sobjects/,
        "$driver: store_subplexes throws on non ARRAYREF";
    throws_ok { $subplex_adaptor->store_subplexes( [ 'SubplexObject' ] ) }
        qr/Argument\smust\sbe\sCrispr::DB::Subplex\sobject/,
        "$driver: store_subplexes throws on string input";
    
    # increment mock object 1's id
    $subplex_id = 3;
    # make new mock object for store injection pools
    my $mock_subplex_2 = Test::MockObject->new();
    $mock_subplex_2->set_isa( 'Crispr::DB::Subplex' );
    $mock_subplex_2->mock( 'db_id', sub{ return 4 } );
    $mock_subplex_2->mock( 'plex', sub{ return $mock_plex } );
    $mock_subplex_2->mock( 'injection_pool', sub{ return $mock_injection_pool } );
    $mock_subplex_2->mock( 'plate_num', sub{ return 1 } );
    
    # 3 tests
    ok( $subplex_adaptor->store_subplexes( [ $mock_subplex, $mock_subplex_2 ] ), "$driver: store_subplexes" );
    row_ok(
       table => 'subplex',
       where => [ subplex_id => 3 ],
       tests => {
           '==' => {
                plex_id => $mock_subplex->plex->db_id,
                plate_num => $mock_subplex->plate_num,
                injection_id => $mock_subplex->injection_pool->db_id,
           },
       },
       label => "$driver: subplex stored",
    );
    row_ok(
       table => 'subplex',
       where => [ subplex_id => 4 ],
       tests => {
           '==' => {
                plex_id => $mock_subplex_2->plex->db_id,
                plate_num => $mock_subplex_2->plate_num,
                injection_id => $mock_subplex_2->injection_pool->db_id,
           },
       },
       label => "$driver: subplex stored",
    );
    
    # 1 test
    throws_ok{ $subplex_adaptor->fetch_by_id( 10 ) } qr/Couldn't retrieve subplex/, 'Subplex does not exist in db';
    
#    # _fetch - 24 tests
#    my $inj_pool_from_db = @{ $subplex_adaptor->_fetch( 'injection_id = ?', [ 3, ] ) }[0];
#    check_attributes( $inj_pool_from_db, $mock_subplex, $driver, '_fetch', );
#    
#    # fetch_by_id - 24 tests
#    $inj_pool_from_db = $subplex_adaptor->fetch_by_id( 4 );
#    check_attributes( $inj_pool_from_db, $mock_subplex_2, $driver, 'fetch_by_id', );
#    
#    # fetch_by_id - 48 tests
#    my @ids = ( 3, 4 );
#    my $inj_pools_from_db = $subplex_adaptor->fetch_by_ids( \@ids );
#    
#    my @subplexes = ( $mock_subplex, $mock_subplex_2 );
#    foreach my $i ( 0..1 ){
#        my $inj_pool_from_db = $inj_pools_from_db->[$i];
#        my $mock_inj_pool = $subplexes[$i];
#        check_attributes( $inj_pool_from_db, $mock_inj_pool, $driver, 'fetch_by_ids', );
#    }
#
#    # fetch_by_name - 25 tests
#    ok( $inj_pool_from_db = $subplex_adaptor->fetch_by_name( '172' ), 'fetch_by_name');
#    check_attributes( $inj_pool_from_db, $mock_subplex, $driver, 'fetch_by_name', );
#
#    # 2 tests
#    ok( $subplex_adaptor->fetch_all_by_date( '2014-10-13' ), 'fetch_all_by_date');
#TODO: {
#    local $TODO = 'methods not implemented yet.';
#    
#    ok( $subplex_adaptor->delete_subplex_from_db ( 'rna' ), 'delete_subplex_from_db');
#
#}
    $test_db_connections{$driver}->destroy();
}

## 12 + 6 * number of guideRNAs per call
#sub check_attributes {
#    my ( $object1, $object2, $driver, $method ) = @_;
#    is( $object1->db_id, $object2->db_id, "$driver: object from db $method - check db_id");
#    is( $object1->pool_name, $object2->pool_name, "$driver: object from db $method - check pool_name");
#    is( abs($object1->cas9_conc - $object2->cas9_conc ) < 0.1, 1, "$driver: object from db $method - check cas9_conc");
#    is( $object1->date, $object2->date, "$driver: object from db $method - check date");
#    is( $object1->line_injected, $object2->line_injected, "$driver: object from db $method - check line_injected");
#    is( $object1->line_raised, $object2->line_raised, "$driver: object from db $method - check line_raised");
#    is( $object1->sorted_by, $object2->sorted_by, "$driver: object from db $method - check sorted_by");
#    
#    is( $object1->cas9_prep->db_id, $object2->cas9_prep->db_id, "$driver: object from db $method - check cas9 db_id");
#    is( $object1->cas9_prep->type, $object2->cas9_prep->type, "$driver: object from db $method - check cas9 type");
#    is( $object1->cas9_prep->prep_type, $object2->cas9_prep->prep_type, "$driver: object from db $method - check cas9 prep_type");
#    is( $object1->cas9_prep->made_by, $object2->cas9_prep->made_by, "$driver: object from db $method - check cas9 made_by");
#    is( $object1->cas9_prep->date, $object2->cas9_prep->date, "$driver: object from db $method - check cas9 date");
#
#    foreach my $i ( 0..scalar @{$object1->guideRNAs} - 1 ){
#        my $g1 = $object1->guideRNAs->[$i];
#        my $g2 = $object2->guideRNAs->[$i];
#        is( $g1->db_id, $g2->db_id, "$driver: object from db $method - check guideRNA db_id");
#        is( $g1->type, $g2->type, "$driver: object from db $method - check guideRNA type");
#        is( abs( $g1->injection_concentration - $g2->injection_concentration) < 0.1, 1, "$driver: object from db $method - check guideRNA concentration");
#        is( $g1->made_by, $g2->made_by, "$driver: object from db $method - check guideRNA made_by");
#        is( $g1->date, $g2->date, "$driver: object from db $method - check guideRNA date");
#        is( $g1->well->position, $g2->well->position, "$driver: object from db $method - check guideRNA well");
#    }
#}
#
