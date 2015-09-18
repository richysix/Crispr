#!/usr/bin/env perl
# sample_adaptor.t
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

use Crispr::DB::SampleAdaptor;
use Crispr::DB::DBConnection;

# Number of tests
Readonly my $TESTS_IN_COMMON => 1 + 21 + 4 + 5 + 4 + 3 + 1 + 7 + 7 + 14 + 8;
#Readonly my $TESTS_IN_COMMON => 1 + 20 + 4 + 13 + 2 + 3 + 24 + 24 + 48 + 25 + 2;
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

# check attributes and methods - 5 + 16 tests
my @attributes = ( qw{ dbname db_connection connection analysis_adaptor injection_pool_adaptor } );

my @methods = (
    qw{ store store_sample store_samples fetch_by_id fetch_by_ids
        fetch_by_name fetch_all_by_analysis_id fetch_all_by_analysis fetch_all_by_injection_id fetch_all_by_injection_pool
        _fetch delete_sample_from_db check_entry_exists_in_db fetch_rows_expecting_single_row fetch_rows_for_generic_select_statement
        _db_error_handling }
);

# DB tests
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
    
    # make mock Plex and InjectionPool objects
    my $mock_plex = Test::MockObject->new();
    $mock_plex->set_isa( 'Crispr::DB::Plex' );
    my $p_id = 1;
    $mock_plex->mock( 'db_id', sub{ my @args = @_; if( $_[1] ){ $p_id = $_[1] } return $p_id; } );
    $mock_plex->mock( 'plex_name', sub{ return 'MPX14' } );
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
    
    # make a new real Sample Adaptor
    my $sample_adaptor = Crispr::DB::SampleAdaptor->new( db_connection => $db_conn, );
    # 1 test
    isa_ok( $sample_adaptor, 'Crispr::DB::SampleAdaptor', "$driver: check object class is ok" );
    
    # check attributes and methods exist 5 + 16 tests
    foreach my $attribute ( @attributes ) {
        can_ok( $sample_adaptor, $attribute );
    }
    foreach my $method ( @methods ) {
        can_ok( $sample_adaptor, $method );
    }
    
    # make a sample mock object
    my $mock_sample = Test::MockObject->new();
    $mock_sample->set_isa( 'Crispr::DB::Sample' );
    my $sample_id = 1;
    $mock_sample->mock( 'db_id', sub{ return $sample_id } );
    $mock_sample->mock( 'injection_pool', sub{ return $mock_injection_pool } );
    $mock_sample->mock( 'generation', sub{ return 'G0' } );
    $mock_sample->mock( 'sample_type', sub{ return 'finclip' } );
    $mock_sample->mock( 'species', sub{ return 'zebrafish' } );
    $mock_sample->mock( 'sample_number', sub { return $sample_id } );
    $mock_sample->mock( 'sample_name', sub{ return join("_", $mock_injection_pool->db_id, $mock_sample->sample_number, ) } );
    
    # check db adaptor attributes - 4 tests
    my $analysis_adaptor;
    ok( $analysis_adaptor = $sample_adaptor->analysis_adaptor(), "$driver: get analysis_adaptor" );
    isa_ok( $analysis_adaptor, 'Crispr::DB::AnalysisAdaptor', "$driver: check analysis_adaptor class" );
    my $injection_pool_adaptor;
    ok( $injection_pool_adaptor = $sample_adaptor->injection_pool_adaptor(), "$driver: get injection_pool_adaptor" );
    isa_ok( $injection_pool_adaptor, 'Crispr::DB::InjectionPoolAdaptor', "$driver: check injection_pool_adaptor class" );
    
    # check store methods 5 tests
    ok( $sample_adaptor->store( $mock_sample ), "$driver: store" );
    row_ok(
       table => 'sample',
       where => [ sample_id => 1 ],
       tests => {
           'eq' => {
                sample_name => $mock_sample->sample_name,
                generation => $mock_sample->generation,
                type => $mock_sample->sample_type,
                species => $mock_sample->species,
           },
           '==' => {
                injection_id => $mock_sample->injection_pool->db_id,
           },
       },
       label => "$driver: sample stored",
    );
    
    # test that store throws properly
    throws_ok { $sample_adaptor->store_sample('Sample') }
        qr/Argument\smust\sbe\sCrispr::DB::Sample\sobject/,
        "$driver: store_sample throws on string input";
    throws_ok { $sample_adaptor->store_sample($mock_cas9_object) }
        qr/Argument\smust\sbe\sCrispr::DB::Sample\sobject/,
        "$driver: store_sample throws if object is not Crispr::DB::Sample";
    
    # check throws ok on attempted duplicate entry
    # for this we need to suppress the warning that is generated as well, hence the nested warning_like test
    # This does not affect the apparent number of tests run
    my $regex = $driver eq 'mysql' ?   qr/Duplicate\sentry/xms
        :                           qr/PRIMARY\sKEY\smust\sbe\sunique/xms;
    
    throws_ok {
        warning_like { $sample_adaptor->store_sample( $mock_sample ) }
            $regex;
    }
        $regex,
        "$driver: store_sample throws because of duplicate entry";
    
    # store sample - 4 tests
    $sample_id = 2;
    ok( $sample_adaptor->store_sample( $mock_sample ), "$driver: store_sample" );
    row_ok(
       table => 'sample',
       where => [ sample_id => 2 ],
       tests => {
           'eq' => {
                sample_name => $mock_sample->sample_name,
                generation => $mock_sample->generation,
                type => $mock_sample->sample_type,
                species => $mock_sample->species,
           },
           '==' => {
                injection_id => $mock_sample->injection_pool->db_id,
           },
       },
       label => "$driver: sample stored 2",
    );
    
    throws_ok { $sample_adaptor->store_samples('SampleObject') }
        qr/Supplied\sargument\smust\sbe\san\sArrayRef\sof\sSample\sobjects/,
        "$driver: store_samples throws on non ARRAYREF";
    throws_ok { $sample_adaptor->store_samples( [ 'SampleObject' ] ) }
        qr/Argument\smust\sbe\sCrispr::DB::Sample\sobject/,
        "$driver: store_samples throws on string input";
    
    # increment mock object 1's id
    $sample_id = 3;
    # make new mock object for store injection pools
    my $mock_sample_2 = Test::MockObject->new();
    $mock_sample_2->set_isa( 'Crispr::DB::Sample' );
    my $sample_id_2 = 4;
    $mock_sample_2->mock( 'db_id', sub{ return $sample_id_2 } );
    $mock_sample_2->mock( 'injection_pool', sub{ return $mock_injection_pool } );
    $mock_sample_2->mock( 'generation', sub{ return 'F1' } );
    $mock_sample_2->mock( 'sample_type', sub{ return 'embryo' } );
    $mock_sample_2->mock( 'species', sub{ return 'zebrafish' } );
    $mock_sample_2->mock( 'sample_number', sub { return $sample_id_2 } );
    $mock_sample_2->mock( 'sample_name', sub{ return join("_", $mock_injection_pool->db_id, $mock_sample_2->sample_number, ) } );
    
    # 3 tests
    ok( $sample_adaptor->store_samples( [ $mock_sample, $mock_sample_2 ] ), "$driver: store_samples" );
    row_ok(
       table => 'sample',
       where => [ sample_id => 3 ],
       tests => {
           'eq' => {
                sample_name => $mock_sample->sample_name,
                generation => $mock_sample->generation,
                type => $mock_sample->sample_type,
                species => $mock_sample->species,
           },
           '==' => {
                injection_id => $mock_sample->injection_pool->db_id,
           },
       },
       label => "$driver: sample stored 3",
    );
    row_ok(
       table => 'sample',
       where => [ sample_id => 4 ],
       tests => {
           'eq' => {
                sample_name => $mock_sample_2->sample_name,
                generation => $mock_sample_2->generation,
                type => $mock_sample_2->sample_type,
                species => $mock_sample_2->species,
           },
           '==' => {
                injection_id => $mock_sample_2->injection_pool->db_id,
           },
       },
       label => "$driver: sample stored 4",
    );
    
    # 1 test
    throws_ok{ $sample_adaptor->fetch_by_id( 10 ) } qr/Couldn't retrieve sample/, 'Sample does not exist in db';
    
    # _fetch - 7 tests
    my $sample_from_db = @{ $sample_adaptor->_fetch( 'sample_id = ?', [ 3, ] ) }[0];
    check_attributes( $sample_from_db, $mock_sample, $driver, '_fetch', );
    
    # fetch_by_id - 7 tests
    $sample_from_db = $sample_adaptor->fetch_by_id( 4 );
    check_attributes( $sample_from_db, $mock_sample_2, $driver, 'fetch_by_id', );
    
    # fetch_by_ids - 14 tests
    my @ids = ( 3, 4 );
    my $samples_from_db = $sample_adaptor->fetch_by_ids( \@ids );
    
    my @samples = ( $mock_sample, $mock_sample_2 );
    foreach my $i ( 0..1 ){
        my $sample_from_db = $samples_from_db->[$i];
        my $mock_sample = $samples[$i];
        check_attributes( $sample_from_db, $mock_sample, $driver, 'fetch_by_ids', );
    }

    # fetch_by_name - 8 tests
    $sample_id = 1;
    ok( $sample_from_db = $sample_adaptor->fetch_by_name( '1_1' ), 'fetch_by_name');
    check_attributes( $sample_from_db, $mock_sample, $driver, 'fetch_by_name', );

#    # 2 tests
#    ok( $sample_adaptor->fetch_all_by_date( '2014-10-13' ), 'fetch_all_by_date');
#TODO: {
#    local $TODO = 'methods not implemented yet.';
#    
#    ok( $sample_adaptor->delete_sample_from_db ( 'rna' ), 'delete_sample_from_db');
#
#}
    $db_connection->destroy();
}

# 7 tests
sub check_attributes {
    my ( $object1, $object2, $driver, $method ) = @_;
    is( $object1->injection_pool->db_id, $object2->injection_pool->db_id, "$driver: object from db $method - check inj db_id");
    is( $object1->injection_pool->pool_name, $object2->injection_pool->pool_name, "$driver: object from db $method - check inj pool_name");
    is( $object1->generation, $object2->generation, "$driver: object from db $method - check generation");
    is( $object1->sample_type, $object2->sample_type, "$driver: object from db $method - check sample_type");
    is( $object1->sample_number, $object2->sample_number, "$driver: object from db $method - check sample_number");
    is( $object1->species, $object2->species, "$driver: object from db $method - check species");
    is( $object1->sample_name, $object2->sample_name, "$driver: object from db $method - check sample_name");
}

