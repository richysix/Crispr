#!/usr/bin/env perl
# injection_pool_adaptor.t
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
use English qw( -no_match_vars );

use Crispr::DB::InjectionPoolAdaptor;
use Crispr::DB::DBConnection;

# Number of tests
Readonly my $TESTS_IN_COMMON => 1 + 16 + 4 + 13 + 2 + 3 + 24 + 24 + 48 + 25 + 2;
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

# check attributes and methods - 3 + 13 tests
my @attributes = ( qw{ dbname db_connection connection } );

my @methods = (
    qw{ store store_injection_pool store_injection_pools fetch_by_id fetch_by_ids
        fetch_by_name fetch_all_by_date _fetch delete_injection_pool_from_db check_entry_exists_in_db
        fetch_rows_expecting_single_row fetch_rows_for_generic_select_statement _db_error_handling }
);

# DB tests
# Module with a function for creating an empty test database
# and returning a database connection
use lib 't/lib';
use TestMethods;

my $test_method_obj = TestMethods->new();
my ( $db_connection_params, $db_connections ) = $test_method_obj->create_test_db();

SKIP: {
    skip 'No database connections available', $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite} if !@{$db_connections};
    
    if( @{$db_connections} == 1 ){
        skip 'Only one database connection available', $TESTS_FOREACH_DBC{sqlite} if $db_connections->[0]->driver eq 'mysql';
        skip 'Only one database connection available', $TESTS_FOREACH_DBC{mysql} if $db_connections->[0]->driver eq 'sqlite';
    }
}

foreach my $db_connection ( @{$db_connections} ){
    my $driver = $db_connection->driver;
    my $dbh = $db_connection->connection->dbh;
    # $dbh is a DBI database handle
    local $Test::DatabaseRow::dbh = $dbh;
    
    # make a real DBConnection object
    my $db_conn = Crispr::DB::DBConnection->new( $db_connection_params->{$driver} );
    
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
    my $statement = "insert into cas9 values( ?, ?, ?, ?, ? );";
    my $sth = $dbh->prepare($statement);
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
    $statement = "insert into target values( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'test_target', 'Zv9', '4', 1, 200, '1', 'zebrafish', 'y', 'GENE0001', 'gene001', 'crispr_test', 75, 2, '2014-10-13');
    # plate 
    $statement = "insert into plate values( ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'CR_000001-', '96', 'crispr', undef, undef, );
    $sth->execute( 2, 'CR_000001h', '96', 'guideRNA_prep', undef, undef, );

    # crRNA
    $statement = "insert into crRNA values( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'crRNA:4:1-23:-1', '4', 1, 23, '-1', 'CACAGATGACAGATAGACAGCGG', 0, 0.81, 0.9, 0.9, 1, 1, 'A01', 3, '2014-12-02' );
    $sth->execute( 2, 'crRNA:4:21-43:1', '4', 21, 43, '1', 'TAGATCAGTAGATCGATAGTAGG', 0, 0.81, 0.9, 0.9, 1, 1, 'B01', 4, '2015-11-30' );
    # guideRNA
    $statement = "insert into guideRNA_prep values( ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 1, 'sgRNA', 50, 'cr1', '2014-10-02', 2, 'A01' );
    $sth->execute( 2, 1, 'sgRNA', 60, 'cr1', '2014-10-02', 2, 'B01' );

    my $mock_injection_pool = Test::MockObject->new();
    $mock_injection_pool->set_isa( 'Crispr::DB::InjectionPool' );
    my $i_id;
    $mock_injection_pool->mock( 'db_id', sub{ my @args = @_; if( $_[1] ){ $i_id = $_[1] } return $i_id; } );
    $mock_injection_pool->mock( 'pool_name', sub{ return '170' } );
    $mock_injection_pool->mock( 'cas9_prep', sub{ return $mock_cas9_prep_object_1 } );
    $mock_injection_pool->mock( 'cas9_conc', sub{ return 200 } );
    $mock_injection_pool->mock( 'date', sub{ return '2014-10-13' } );
    $mock_injection_pool->mock( 'line_injected', sub{ return 'H1530' } );
    $mock_injection_pool->mock( 'line_raised', sub{ return undef } );
    $mock_injection_pool->mock( 'sorted_by', sub{ return 'cr_1' } );
    $mock_injection_pool->mock( 'guideRNAs', sub{ return [ $mock_gRNA_1, $mock_gRNA_2, ] } );
    $mock_injection_pool->mock( 'info', sub{ return (
                                                $mock_injection_pool->db_id || 'NULL',
                                                $mock_injection_pool->pool_name,
                                                $mock_injection_pool->cas9_conc,
                                                $mock_injection_pool->date || 'NULL',
                                                $mock_injection_pool->line_injected,
                                                $mock_injection_pool->line_raised || 'NULL',
                                                $mock_injection_pool->sorted_by || 'NULL',
                                                ) } );
    
    # make a new real InjectionPool Adaptor
    my $injection_pool_adaptor = Crispr::DB::InjectionPoolAdaptor->new( db_connection => $db_conn, );
    # 1 test
    isa_ok( $injection_pool_adaptor, 'Crispr::DB::InjectionPoolAdaptor', "$driver: check object class is ok" );
    
    # check attributes and methods exist 3 + 13 tests
    foreach my $attribute ( @attributes ) {
        can_ok( $injection_pool_adaptor, $attribute );
    }
    foreach my $method ( @methods ) {
        can_ok( $injection_pool_adaptor, $method );
    }
    
    # check db adaptor attributes - 4 tests
    my $cas9_prep_adaptor;
    ok( $cas9_prep_adaptor = $injection_pool_adaptor->cas9_prep_adaptor(), "$driver: get cas9_prep_adaptor" );
    isa_ok( $cas9_prep_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: check cas9_prep_adaptor class" );
    my $crRNA_adaptor;
    ok( $crRNA_adaptor = $injection_pool_adaptor->crRNA_adaptor(), "$driver: get crRNA_adaptor" );
    isa_ok( $crRNA_adaptor, 'Crispr::DB::crRNAAdaptor', "$driver: check crRNA_adaptor class" );
    
    # check store methods 12 tests
    ok( $injection_pool_adaptor->store( $mock_injection_pool ), "$driver: store" );
    row_ok(
       table => 'injection',
       where => [ injection_id => 1 ],
       tests => {
           'eq' => {
                injection_name => $mock_injection_pool->pool_name,
                line_injected  => $mock_injection_pool->line_injected,
                line_raised  => $mock_injection_pool->line_raised,
                sorted_by => $mock_injection_pool->sorted_by,
                date => $mock_injection_pool->date,
           },
           '==' => {
                cas9_prep_id => $mock_cas9_prep_object_1->db_id,
                cas9_concentration => $mock_injection_pool->cas9_conc,
           },
       },
       label => "$driver: injection pool stored",
    );
    my @rows;
    row_ok(
        table => 'injection_pool',
        where => [ injection_id => 1 ],
        store_rows => \@rows,
    );
    my $id = 1;
    foreach my $row ( @rows ){
        is( $row->{'crRNA_id'}, $id, "$driver check crRNA ids");
        $id++;
    }
    
    # test that store throws properly
    throws_ok { $injection_pool_adaptor->store_injection_pool('InjectionPool') }
        qr/Argument\smust\sbe\sCrispr::DB::InjectionPool\sobject/,
        "$driver: store_injection_pool throws on string input";
    throws_ok { $injection_pool_adaptor->store_injection_pool($mock_cas9_object) }
        qr/Argument\smust\sbe\sCrispr::DB::InjectionPool\sobject/,
        "$driver: store_injection_pool throws if object is not Crispr::DB::InjectionPool";
    
    ## check throws ok on attempted duplicate entry
    ## for this we need to suppress the warning that is generated as well, hence the nested warning_like test
    ## This does not affect the apparent number of tests run
    #my $regex = $driver eq 'mysql' ?   qr/Duplicate\sentry/xms
    #    :                           qr/PRIMARY\sKEY\smust\sbe\sunique/xms;
    
    #throws_ok {
    #    warning_like { $injection_pool_adaptor->store_injection_pool( $mock_injection_pool) }
    #        $regex;
    #}
    #    $regex,
    #    "$driver: store_injection_pool throws because of duplicate entry";
    warning_like { $injection_pool_adaptor->store_injection_pool( $mock_injection_pool) }
        qr/Injection\salready\sexists\sin\sthe\sdatabase/, 'check warning if injection already exists';
    
    $i_id = 2;
    $mock_injection_pool->mock( 'pool_name', sub{ return '171' } );
    ok( $injection_pool_adaptor->store_injection_pool( $mock_injection_pool ), "$driver: store_injection_pool" );
    row_ok(
       table => 'injection',
       where => [ injection_id => 2 ],
       tests => {
           'eq' => {
                injection_name => $mock_injection_pool->pool_name,
                line_injected  => $mock_injection_pool->line_injected,
                line_raised  => $mock_injection_pool->line_raised,
                sorted_by => $mock_injection_pool->sorted_by,
                date => $mock_injection_pool->date,
           },
           '==' => {
                cas9_prep_id => $mock_cas9_prep_object_1->db_id,
                cas9_concentration => $mock_injection_pool->cas9_conc,
           },
       },
       label => "$driver: injection pool stored",
    );
    @rows = ();
    row_ok(
        table => 'injection_pool',
        where => [ injection_id => 2 ],
        store_rows => \@rows,
    );
    $id = 1;
    foreach my $row ( @rows ){
        is( $row->{'crRNA_id'}, $id, "$driver check crRNA ids");
        $id++;
    }
    
    # throws ok - 2 tests
    throws_ok { $injection_pool_adaptor->store_injection_pools('InjectionPoolObject') }
        qr/Supplied\sargument\smust\sbe\san\sArrayRef\sof\sInjectionPool\sobjects/,
        "$driver: store_injection_pools throws on non ARRAYREF";
    throws_ok { $injection_pool_adaptor->store_injection_pools( [ 'InjectionPoolObject' ] ) }
        qr/Argument\smust\sbe\sCrispr::DB::InjectionPool\sobject/,
        "$driver: store_injection_pools throws on string input";
    
    # increment mock object 1's id
    $i_id = 3;
    $mock_injection_pool->mock( 'pool_name', sub{ return '172' } );
    # make new mock object for store injection pools
    my $mock_injection_pool_2 = Test::MockObject->new();
    $mock_injection_pool_2->set_isa( 'Crispr::DB::InjectionPool' );
    $mock_injection_pool_2->mock( 'db_id', sub{ return 4; } );
    $mock_injection_pool_2->mock( 'pool_name', sub{ return '173' } );
    $mock_injection_pool_2->mock( 'cas9_prep', sub{ return $mock_cas9_prep_object_1 } );
    $mock_injection_pool_2->mock( 'cas9_conc', sub{ return 200 } );
    $mock_injection_pool_2->mock( 'guideRNA_conc', sub{ return 10 } );
    $mock_injection_pool_2->mock( 'guideRNA_type', sub{ return 'sgRNA' } );
    $mock_injection_pool_2->mock( 'date', sub{ return '2014-10-13' } );
    $mock_injection_pool_2->mock( 'line_injected', sub{ return 'H1530' } );
    $mock_injection_pool_2->mock( 'line_raised', sub{ return undef } );
    $mock_injection_pool_2->mock( 'sorted_by', sub{ return 'cr_1' } );
    $mock_injection_pool_2->mock( 'guideRNAs', sub{ return [ $mock_gRNA_1, $mock_gRNA_2, ] } );
    
    # 3 tests
    ok( $injection_pool_adaptor->store_injection_pools( [ $mock_injection_pool, $mock_injection_pool_2 ] ), "$driver: store_injection_pools" );
    row_ok(
       table => 'injection',
       where => [ injection_id => 3 ],
       tests => {
           'eq' => {
                injection_name => $mock_injection_pool->pool_name,
                line_injected  => $mock_injection_pool->line_injected,
                line_raised  => $mock_injection_pool->line_raised,
                sorted_by => $mock_injection_pool->sorted_by,
                date => $mock_injection_pool->date,
           },
           '==' => {
                cas9_prep_id => $mock_cas9_prep_object_1->db_id,
                cas9_concentration => $mock_injection_pool->cas9_conc,
           },
       },
       label => "$driver: injection pool stored",
    );
    row_ok(
       table => 'injection',
       where => [ injection_id => 4 ],
       tests => {
           'eq' => {
                injection_name => $mock_injection_pool_2->pool_name,
                line_injected  => $mock_injection_pool_2->line_injected,
                line_raised  => $mock_injection_pool_2->line_raised,
                sorted_by => $mock_injection_pool_2->sorted_by,
                date => $mock_injection_pool_2->date,
           },
           '==' => {
                cas9_prep_id => $mock_cas9_prep_object_1->db_id,
                cas9_concentration => $mock_injection_pool_2->cas9_conc,
           },
       },
       label => "$driver: injection pool stored",
    );
    
    #throws_ok{ $injection_pool_adaptor->fetch_by_id( 10 ) } qr/Couldn't retrieve injection_pool/, 'Injection Pool does not exist in db';
    
    # _fetch - 24 tests
    my $inj_pool_from_db = @{ $injection_pool_adaptor->_fetch( 'injection_id = ?', [ 3, ] ) }[0];
    check_attributes( $inj_pool_from_db, $mock_injection_pool, $driver, '_fetch', );
    
    # fetch_by_id - 24 tests
    $inj_pool_from_db = $injection_pool_adaptor->fetch_by_id( 4 );
    check_attributes( $inj_pool_from_db, $mock_injection_pool_2, $driver, 'fetch_by_id', );
    
    # fetch_by_id - 48 tests
    my @ids = ( 3, 4 );
    my $inj_pools_from_db = $injection_pool_adaptor->fetch_by_ids( \@ids );
    
    my @injection_pools = ( $mock_injection_pool, $mock_injection_pool_2 );
    foreach my $i ( 0..1 ){
        my $inj_pool_from_db = $inj_pools_from_db->[$i];
        my $mock_inj_pool = $injection_pools[$i];
        check_attributes( $inj_pool_from_db, $mock_inj_pool, $driver, 'fetch_by_ids', );
    }

    # fetch_by_name - 25 tests
    ok( $inj_pool_from_db = $injection_pool_adaptor->fetch_by_name( '172' ), 'fetch_by_name');
    check_attributes( $inj_pool_from_db, $mock_injection_pool, $driver, 'fetch_by_name', );

    # 2 tests
    ok( $injection_pool_adaptor->fetch_all_by_date( '2014-10-13' ), 'fetch_all_by_date');
TODO: {
    local $TODO = 'methods not implemented yet.';
    
    ok( $injection_pool_adaptor->delete_injection_pool_from_db ( 'rna' ), 'delete_injection_pool_from_db');

}
    $db_connection->destroy();
}

# 12 + 6 * number of guideRNAs per call
sub check_attributes {
    my ( $object1, $object2, $driver, $method ) = @_;
    is( $object1->db_id, $object2->db_id, "$driver: object from db $method - check db_id");
    is( $object1->pool_name, $object2->pool_name, "$driver: object from db $method - check pool_name");
    is( abs($object1->cas9_conc - $object2->cas9_conc ) < 0.1, 1, "$driver: object from db $method - check cas9_conc");
    is( $object1->date, $object2->date, "$driver: object from db $method - check date");
    is( $object1->line_injected, $object2->line_injected, "$driver: object from db $method - check line_injected");
    is( $object1->line_raised, $object2->line_raised, "$driver: object from db $method - check line_raised");
    is( $object1->sorted_by, $object2->sorted_by, "$driver: object from db $method - check sorted_by");
    
    is( $object1->cas9_prep->db_id, $object2->cas9_prep->db_id, "$driver: object from db $method - check cas9 db_id");
    is( $object1->cas9_prep->type, $object2->cas9_prep->type, "$driver: object from db $method - check cas9 type");
    is( $object1->cas9_prep->prep_type, $object2->cas9_prep->prep_type, "$driver: object from db $method - check cas9 prep_type");
    is( $object1->cas9_prep->made_by, $object2->cas9_prep->made_by, "$driver: object from db $method - check cas9 made_by");
    is( $object1->cas9_prep->date, $object2->cas9_prep->date, "$driver: object from db $method - check cas9 date");

    foreach my $i ( 0..scalar @{$object1->guideRNAs} - 1 ){
        my $g1 = $object1->guideRNAs->[$i];
        my $g2 = $object2->guideRNAs->[$i];
        is( $g1->db_id, $g2->db_id, "$driver: object from db $method - check guideRNA db_id");
        is( $g1->type, $g2->type, "$driver: object from db $method - check guideRNA type");
        is( abs( $g1->injection_concentration - $g2->injection_concentration) < 0.1, 1, "$driver: object from db $method - check guideRNA concentration");
        is( $g1->made_by, $g2->made_by, "$driver: object from db $method - check guideRNA made_by");
        is( $g1->date, $g2->date, "$driver: object from db $method - check guideRNA date");
        is( $g1->well->position, $g2->well->position, "$driver: object from db $method - check guideRNA well");
    }
}

