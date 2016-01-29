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
Readonly my $TESTS_IN_COMMON => 1 + 21 + 4 + 7 + 5 + 3 + 4 + 16 + 1 + 10 + 9 + 18 + 38 + 11 + 19 + 21 + 2;
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

my $mock_obj_args = {
    add_to_db => 1,
};
foreach my $db_connection ( @{$db_connections} ){
    my $driver = $db_connection->driver;
    my $dbh = $db_connection->connection->dbh;
    # $dbh is a DBI database handle
    local $Test::DatabaseRow::dbh = $dbh;

    # make a real DBConnection object
    my $db_conn = Crispr::DB::DBConnection->new( $db_connection_params->{$driver} );

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
    $statement = "insert into target values( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'test_target', 'Zv9', '4', 1, 200, '1', 'zebrafish', 'y', 'GENE0001', 'gene001', 'crispr_test', 75, 9, '2014-10-13');
    # plate
    $statement = "insert into plate values( ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'CR_000001-', '96', 'crispr', undef, undef, );
    $sth->execute( 2, 'CR_000001h', '96', 'guideRNA_prep', undef, undef, );

    # crRNA
    $statement = "insert into crRNA values( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'crRNA:4:1-23:-1', '4', 1, 23, '-1', 'CACAGATGACAGATAGACAGCGG', 0, 0.81, 0.9, 0.9, 1, 1, 'A01', 10, '2015-11-10' );
    $sth->execute( 2, 'crRNA:4:21-43:1', '4', 21, 43, '1', 'TAGATCAGTAGATCGATAGTAGG', 0, 0.81, 0.9, 0.9, 1, 1, 'B01', 11, '2015-12-20' );
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
    ## add directly to db
    #$statement = "insert into injection values( ?, ?, ?, ?, ?, ?, ?, ? );";
    #$sth = $dbh->prepare($statement);
    #$sth->execute(
    #    $mock_injection_pool->db_id,
    #    $mock_injection_pool->pool_name,
    #    $mock_cas9_prep_object_1->db_id,
    #    $mock_cas9_prep_object_1->concentration,
    #    $mock_injection_pool->date,
    #    $mock_injection_pool->line_injected,
    #    $mock_injection_pool->line_raised,
    #    $mock_injection_pool->sorted_by,
    #);
    #$statement = "insert into injection_pool values( ?, ?, ?, ? );";
    #$sth = $dbh->prepare($statement);
    #$sth->execute(
    #    $mock_injection_pool->db_id,
    #    $mock_crRNA_object_1->crRNA_id,
    #    $mock_gRNA_1->db_id,
    #    $mock_gRNA_1->injection_concentration,
    #);

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

    my $mock_well_object = Test::MockObject->new();
    $mock_well_object->set_isa( 'Labware::Well' );
    $mock_well_object->mock( 'position', sub { return 'A01' } );

    $mock_sample->mock( 'db_id', sub{ return $sample_id } );
    $mock_sample->mock( 'injection_pool', sub{ return undef } );
    $mock_sample->mock( 'generation', sub{ return 'G0' } );
    $mock_sample->mock( 'sample_type', sub{ return 'finclip' } );
    $mock_sample->mock( 'species', sub{ return 'zebrafish' } );
    $mock_sample->mock( 'sample_number', sub { return $sample_id } );
    $mock_sample->mock( 'well', sub { return undef } );
    $mock_sample->mock( 'cryo_box', sub { return undef } );
    $mock_sample->mock( 'sample_name', sub{ return join("_", $mock_injection_pool->pool_name, $mock_sample->sample_number, ) } );
    $mock_sample->mock( 'alleles', sub{ return undef; } );

    # check db adaptor attributes - 4 tests
    my $analysis_adaptor;
    ok( $analysis_adaptor = $sample_adaptor->analysis_adaptor(), "$driver: get analysis_adaptor" );
    isa_ok( $analysis_adaptor, 'Crispr::DB::AnalysisAdaptor', "$driver: check analysis_adaptor class" );
    my $injection_pool_adaptor;
    ok( $injection_pool_adaptor = $sample_adaptor->injection_pool_adaptor(), "$driver: get injection_pool_adaptor" );
    isa_ok( $injection_pool_adaptor, 'Crispr::DB::InjectionPoolAdaptor', "$driver: check injection_pool_adaptor class" );

    # check store methods 7 tests
    throws_ok { $sample_adaptor->store( $mock_sample ) }
        qr/One of the Sample objects does not contain an InjectionPool object/,
        'check store throws if sample does not have an injection pool';

    # check injection pool info
    $mock_injection_pool->mock( 'pool_name', sub{ return undef } );
    $mock_sample->mock( 'injection_pool', sub{ return $mock_injection_pool } );
    throws_ok { $sample_adaptor->store( $mock_sample ) }
        qr/One of the Sample objects contains an InjectionPool object with neither a db_id nor an injection_name/,
        'check store throws if injection has neither db_id nor name';

    $mock_injection_pool->mock( 'pool_name', sub{ return '170' } );
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
                well_id => $mock_sample->well,
                cryo_box => $mock_sample->cryo_box,
           },
           '==' => {
                injection_id => $mock_sample->injection_pool->db_id,
           },
       },
       label => "$driver: sample stored",
    );
    # reset db_id on mock injection pool
    $i_id = undef;

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
        :                           qr/unique/xmsi;

    throws_ok {
        warning_like { $sample_adaptor->store_sample( $mock_sample ) }
            $regex;
    }
        $regex,
        "$driver: store_sample throws because of duplicate entry";

    # store sample - 5 tests
    $sample_id = 2;
    # change well from undef to mock well and change mocked sample_name method
    $mock_sample->mock( 'well', sub { return $mock_well_object } );
    $mock_sample->mock( 'sample_name', sub{ return join("_", $mock_injection_pool->pool_name, $mock_sample->well->position, ) } );
    # change well_id to solve duplicate sample name problem
    #$mock_well_object->mock( 'position', sub { return 'A02' } );
    # add injection pool db_id

    $i_id = 1;
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
                well_id => $mock_sample->well->position,
                cryo_box => $mock_sample->cryo_box,
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
    # check store throws on duplicate sample_name
    $regex = $driver eq 'mysql' ?   qr/Duplicate entry/
        :                           qr/unique/xmsi;
    throws_ok {
        warning_like { $sample_adaptor->store_sample( $mock_sample ) }
            $regex;
    }
        $regex, "$driver: store sample throws with duplicate sample_name";

    # change well_id to solve duplicate sample name problem
    $mock_well_object->mock( 'position', sub { return 'A03' } );

    # make new mock object for store samples
    my $mock_sample_2 = Test::MockObject->new();
    $mock_sample_2->set_isa( 'Crispr::DB::Sample' );
    my $sample_id_2 = 4;

    my $mock_well_object_2 = Test::MockObject->new();
    $mock_well_object_2->set_isa( 'Labware::Well' );
    $mock_well_object_2->mock( 'position', sub { return undef } );

    $mock_sample_2->mock( 'db_id', sub{ return $sample_id_2 } );
    $mock_sample_2->mock( 'injection_pool', sub{ return $mock_injection_pool } );
    $mock_sample_2->mock( 'generation', sub{ return 'F1' } );
    $mock_sample_2->mock( 'sample_type', sub{ return 'embryo' } );
    $mock_sample_2->mock( 'species', sub{ return 'zebrafish' } );
    $mock_sample_2->mock( 'sample_number', sub { return $sample_id_2 } );
    $mock_sample_2->mock( 'well', sub { return $mock_well_object_2 } );
    $mock_sample_2->mock( 'cryo_box', sub { return 'Cr_Sperm12' } );
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
                well_id => $mock_sample->well->position,
                cryo_box => $mock_sample->cryo_box,
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
                well_id => $mock_sample_2->well->position,
                cryo_box => $mock_sample_2->cryo_box,
           },
           '==' => {
                injection_id => $mock_sample_2->injection_pool->db_id,
           },
       },
       label => "$driver: sample stored 4",
    );

    # check store alleles for sample - 4 tests
    throws_ok{ $sample_adaptor->store_alleles_for_sample() }
        qr/UNDEFINED SAMPLE/, "$driver: store_alleles_for_sample throws on undefined sample";
    throws_ok{ $sample_adaptor->store_alleles_for_sample( $mock_sample ) }
        qr/UNDEFINED ALLELES/, "$driver: store_alleles_for_sample throws on undefined alleles";

    # get new mock allele object
    $mock_obj_args->{mock_crRNA} = $mock_crRNA_object_1;
    my ( $mock_allele, $mock_crRNA_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'allele',
        $mock_obj_args, $db_connection );
    warn Dumper( $mock_allele );
    # add it to the mock sample
    $mock_sample->mock('alleles', sub { return [ $mock_allele ]; } );

    ok( $sample_adaptor->store_alleles_for_sample( $mock_sample ),
        "$driver: store_alleles_for_sample");
    row_ok(
       table => 'sample_allele',
       where => [ sample_id => $mock_sample->db_id ],
       tests => {
           '==' => {
                allele_id => $mock_allele->db_id,
                percentage_of_reads => $mock_allele->percent_of_reads,
           },
       },
       label => "$driver: allele stored 1",
    );

    # store sequencing results - 16 tests
    $mock_sample->mock('total_reads', sub{ return 10000 });
    my $seq_results = {
        1 => {
            fail => 0,
            num_indels => 5,
            total_percentage => 21,
            percentage_major_variant => 12,
        },
        2 => {
            fail => 1,
            num_indels => 2,
            total_percentage => 4.3,
            percentage_major_variant => 3.1,
        },
    };

    ok( $sample_adaptor->store_sequencing_results( $mock_sample, $seq_results ),
        "$driver: store_sequencing_results");
    my @rows;
    row_ok(
        sql => "SELECT * FROM sequencing_results WHERE sample_id = 3;",
        store_rows => \@rows,
        label => "$driver: sequencing_results for sample 3",
    );
    my @expected_results = (
        [ 3, 1, 0, 5, 21, 12, 10000 ],
        [ 3, 2, 1, 2, 4.3, 3.1, 10000 ],
    );
    my $s_id = 3;
    foreach my $row ( @rows ){
        my $ex = shift @expected_results;
        is( $row->{sample_id}, $ex->[0], "$driver: store_sequencing_results check sample_id - $s_id" );
        is( $row->{crRNA_id}, $ex->[1], "$driver: store_sequencing_results check crRNA_id - $s_id" );
        is( $row->{fail}, $ex->[2], "$driver: store_sequencing_results check fail - $s_id" );
        is( $row->{num_indels}, $ex->[3], "$driver: store_sequencing_results check num_indels - $s_id" );
        is( $row->{total_percentage_of_reads}, $ex->[4], "$driver: store_sequencing_results check total_percentage_of_reads - $s_id" );
        is( $row->{percentage_major_variant}, $ex->[5], "$driver: store_sequencing_results check percentage_major_variant - $s_id" );
        is( $row->{total_reads}, $ex->[6], "$driver: store_sequencing_results check total_reads - $s_id" );
        $s_id++;
    }


    # 1 test
    throws_ok{ $sample_adaptor->fetch_by_id( 10 ) } qr/Couldn't retrieve sample/, 'Sample does not exist in db';

    # _fetch - 10 tests
    ok( $sample_adaptor->_fetch(), '_fetch without where clause');
    my $sample_from_db = @{ $sample_adaptor->_fetch( 'sample_id = ?', [ 3, ] ) }[0];
    check_attributes( $sample_from_db, $mock_sample, $driver, '_fetch', );

    # fetch_by_id - 9 tests
    $sample_from_db = $sample_adaptor->fetch_by_id( 4 );
    check_attributes( $sample_from_db, $mock_sample_2, $driver, 'fetch_by_id', );

    # fetch_by_ids - 18 tests
    my @ids = ( 3, 4 );
    my $samples_from_db = $sample_adaptor->fetch_by_ids( \@ids );

    my @samples = ( $mock_sample, $mock_sample_2 );
    foreach my $i ( 0..1 ){
        my $sample_from_db = $samples_from_db->[$i];
        my $mock_sample = $samples[$i];
        check_attributes( $sample_from_db, $mock_sample, $driver, 'fetch_by_ids', );
    }

    # fetch all by injection id - 19 tests
    throws_ok { $sample_adaptor->fetch_all_by_injection_id( 171 ) }
        qr/Couldn't retrieve samples/,
        'fetch_all_by_injection_id throws on non-existent injection_id';

    $samples_from_db = $sample_adaptor->fetch_all_by_injection_id( 1 );
    foreach my $i ( 2..3 ){
        my $sample_from_db = $samples_from_db->[$i];
        my $mock_sample = $samples[$i-2];
        check_attributes( $sample_from_db, $mock_sample, $driver, 'fetch_by_ids', );
    }

    # fetch_all_by_injection_pool - 19 tests
    $i_id = 171;
    throws_ok { $sample_adaptor->fetch_all_by_injection_pool( $mock_injection_pool ) }
        qr/Couldn't retrieve samples/,
        'fetch_all_by_injection_pool throws on non-existent injection_id';

    $i_id = 1;
    $samples_from_db = $sample_adaptor->fetch_all_by_injection_pool( $mock_injection_pool );
    foreach my $i ( 2..3 ){
        my $sample_from_db = $samples_from_db->[$i];
        my $mock_sample = $samples[$i-2];
        check_attributes( $sample_from_db, $mock_sample, $driver, 'fetch_by_ids', );
    }

    # fetch_by_name - 11 tests
    throws_ok { $sample_adaptor->fetch_by_name( '170_A05' ) }
        qr/Couldn't retrieve sample/,
        'fetch_by_name throws on non-existent sample';
    ok( $sample_from_db = $sample_adaptor->fetch_by_name( '170_A03' ), 'fetch_by_name');
    check_attributes( $sample_from_db, $mock_sample, $driver, 'fetch_by_name', );

    # add analysis
    $statement = "insert into analysis values( ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 1, '2014-10-02', '2014-10-02' );

    $statement = "insert into primer values( ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'ACGATAGACGATA', '13', 13535, 13635, '1', undef, undef, undef );
    $sth->execute( 2, 'ACGATAGACGATA', '13', 13535, 13635, '1', undef, undef, undef );

    $statement = "insert into primer_pair values( ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'ext', 1, 2, '13', 13535, 13635, '1', 250 );

    # increment mock object 1's id
    $sample_id = 5;
    # change well_id to solve duplicate sample name problem
    $mock_well_object->mock( 'position', sub { return 'A06' } );

    $sample_id_2 = 6;
    $mock_well_object_2->mock( 'position', sub { return undef } );
    # store new samples
    ok( $sample_adaptor->store_samples( [ $mock_sample, $mock_sample_2 ] ), "$driver: store_samples 5 & 6" );

    my $mock_analysis = Test::MockObject->new();
    $mock_analysis->set_isa( 'Crispr::DB::Analysis' );
    $mock_analysis->mock( 'db_id', sub { return 2 } );

    $statement = "insert into analysis_information values( ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 5, 1, 5, 1, 'A06' );
    $sth->execute( 1, 6, 1, 6, 1, 'A07' );

    # fetch_all_by_analysis_id - 19 tests
    throws_ok { $sample_adaptor->fetch_all_by_analysis_id( 2 ) }
        qr/Couldn't retrieve samples/,
        'fetch_all_by_analysis_id throws on no samples returned';
    $samples_from_db = $sample_adaptor->fetch_all_by_analysis_id( 1 );
    foreach my $i ( 0..1 ){
        my $sample_from_db = $samples_from_db->[$i];
        my $mock_sample = $samples[$i];
        check_attributes( $sample_from_db, $mock_sample, $driver, 'fetch_all_by_analysis_id', );
    }

    # fetch_all_by_analysis - 21 tests
    throws_ok { $sample_adaptor->fetch_all_by_analysis( 2 ) }
        qr/Argument must be a Crispr::DB::Analysis object/,
        'fetch_all_by_analysis throws on string input';
    throws_ok { $sample_adaptor->fetch_all_by_analysis( $mock_injection_pool ) }
        qr/Argument must be a Crispr::DB::Analysis object/,
        'fetch_all_by_analysis throws on object of wrong type';
    throws_ok { $sample_adaptor->fetch_all_by_analysis_id( $mock_analysis ) }
        qr/Couldn't retrieve samples/,
        'fetch_all_by_analysis throws on no samples returned';

    $mock_analysis->mock( 'db_id', sub { return 1 } );
    $samples_from_db = $sample_adaptor->fetch_all_by_analysis( $mock_analysis );
    foreach my $i ( 0..1 ){
        my $sample_from_db = $samples_from_db->[$i];
        my $mock_sample = $samples[$i];
        check_attributes( $sample_from_db, $mock_sample, $driver, 'fetch_all_by_analysis_id', );
    }


    # 2 tests
TODO: {
    local $TODO = 'methods not implemented yet.';

    ok( $sample_adaptor->delete_sample_from_db ( $mock_sample ), 'delete_sample_from_db');
}
    $db_connection->destroy();
}

# 9 tests
sub check_attributes {
    my ( $object1, $object2, $driver, $method ) = @_;
    is( $object1->injection_pool->db_id, $object2->injection_pool->db_id, "$driver: object from db $method - check inj db_id");
    is( $object1->injection_pool->pool_name, $object2->injection_pool->pool_name, "$driver: object from db $method - check inj pool_name");
    is( $object1->generation, $object2->generation, "$driver: object from db $method - check generation");
    is( $object1->sample_type, $object2->sample_type, "$driver: object from db $method - check sample_type");
    is( $object1->sample_number, $object2->sample_number, "$driver: object from db $method - check sample_number");
    is( $object1->species, $object2->species, "$driver: object from db $method - check species");
    if( !defined $object1->well || !defined $object2->well ){
        is( $object1->well, undef, "$driver: object from db $method - check well");
    }
    else{
        is( $object1->well->position, $object2->well->position, "$driver: object from db $method - check well");
    }
    is( $object1->cryo_box, $object2->cryo_box, "$driver: object from db $method - check cryo_box");
    is( $object1->sample_name, $object2->sample_name, "$driver: object from db $method - check sample_name");
}
