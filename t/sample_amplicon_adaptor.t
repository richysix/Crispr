#!/usr/bin/env perl
# sample_amplicon_adaptor.t
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

use Crispr::DB::SampleAmpliconAdaptor;
use Crispr::DB::DBConnection;

# Number of tests
Readonly my $TESTS_IN_COMMON => 1 + 16 + 4 + 4 + 4 + 3 + 5;
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

# check attributes and methods - 5 + 11 tests
my @attributes = ( qw{ dbname db_connection connection plex_adaptor sample_adaptor } );

my @methods = (
    qw{ store store_sample_amplicon store_sample_amplicons fetch_all_by_analysis_id fetch_all_by_analysis
        _fetch delete_sample_amplicon_from_db check_entry_exists_in_db fetch_rows_expecting_single_row fetch_rows_for_generic_select_statement
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

foreach my $db_connection ( @{$db_connections} ){
    my $driver = $db_connection->driver;
    my $dbh = $db_connection->connection->dbh;
    # $dbh is a DBI database handle
    local $Test::DatabaseRow::dbh = $dbh;
    
    # make a real DBConnection object
    my $db_conn = Crispr::DB::DBConnection->new( $db_connection_params->{$driver} );
    
    # make mock Plex and InjectionPool and SampleAmplicon objects
    my $mock_plex = Test::MockObject->new();
    $mock_plex->set_isa( 'Crispr::DB::Plex' );
    my $p_id = 1;
    my $plex_name = 'MPX14';
    $mock_plex->mock( 'db_id', sub{ my @args = @_; if( $_[1] ){ $p_id = $_[1] } return $p_id; } );
    $mock_plex->mock( 'plex_name', sub{ return lc( $plex_name ) } );
    $mock_plex->mock( 'run_id', sub{ return 13831 } );
    $mock_plex->mock( 'sample_amplicon_started', sub{ return '2014-09-27' } );
    $mock_plex->mock( 'sample_amplicon_finished', sub{ return undef } );

    # insert directly into db
    my $statement = "insert into plex values( ?, ?, ?, ?, ? );";
    my $sth = $dbh->prepare($statement);
    $sth->execute( $mock_plex->db_id,
        $mock_plex->plex_name,
        $mock_plex->run_id,
        $mock_plex->sample_amplicon_started,
        $mock_plex->sample_amplicon_finished,
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
    
    my $mock_well_1 = Test::MockObject->new();
    $mock_well_1->set_isa( 'Labware::Well' );
    #$mock_well->mock( 'plate', sub{ return $mock_plate } );
    #$mock_well->mock( 'plate_type', sub{ return '96' } );
    $mock_well_1->mock( 'position', sub{ return 'A01' } );
    
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
    $mock_gRNA_1->mock( 'well', sub{ return $mock_well_1 } );
    
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
    
    # make mock Sample and PrimerPair objects
    my $mock_sample_1 = Test::MockObject->new();
    $mock_sample_1->set_isa( 'Crispr::DB::Sample' );
    $mock_sample_1->mock( 'db_id', sub { return 1 } );
    $mock_sample_1->mock( 'sample_name', sub { return '170_1' } );
    $mock_sample_1->mock( 'sample_number', sub { return 1 } );
    $mock_sample_1->mock( 'injection_id', sub { return $i_id } );
    $mock_sample_1->mock( 'generation', sub { return 'G0' } );
    $mock_sample_1->mock( 'type', sub { return 'embryo' } );
    $mock_sample_1->mock( 'species', sub { return 'zebrafish' } );
    $mock_sample_1->mock( 'well', sub { return $mock_well_1 } );
    $mock_sample_1->mock( 'cryo_box', sub { return 'Cr_Sperm12' } );
    
    my $mock_sample_2 = Test::MockObject->new();
    $mock_sample_2->set_isa( 'Crispr::DB::Sample' );
    $mock_sample_2->mock( 'db_id', sub { return 2 } );
    $mock_sample_2->mock( 'sample_name', sub { return '170_2' } );
    $mock_sample_2->mock( 'sample_number', sub { return 2 } );
    $mock_sample_2->mock( 'injection_id', sub { return $i_id } );
    $mock_sample_2->mock( 'generation', sub { return 'G0' } );
    $mock_sample_2->mock( 'type', sub { return 'embryo' } );
    $mock_sample_2->mock( 'species', sub { return 'zebrafish' } );
    $mock_sample_2->mock( 'well', sub { return $mock_well_2 } );
    $mock_sample_2->mock( 'cryo_box', sub { return 'Cr_Sperm12' } );
    
    # add samples to db
    $statement = "insert into sample values( ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute(
        $mock_sample_1->db_id,
        $mock_sample_1->sample_name,
        $mock_sample_1->sample_number,
        $mock_sample_1->injection_id,
        $mock_sample_1->generation,
        $mock_sample_1->type,
        $mock_sample_1->species,
        $mock_sample_1->well->position,
        $mock_sample_1->cryo_box,
    );
    $sth->execute(
        $mock_sample_2->db_id,
        $mock_sample_2->sample_name,
        $mock_sample_2->sample_number,
        $mock_sample_2->injection_id,
        $mock_sample_2->generation,
        $mock_sample_2->type,
        $mock_sample_2->species,
        $mock_sample_2->well->position,
        $mock_sample_2->cryo_box,
    );
    
    # make mock primer and primer pair objects
    my $mock_left_primer = Test::MockObject->new();
    $mock_left_primer->mock( 'sequence', sub { return 'CGACAGTAGACAGTTAGACGAG' } );
    $mock_left_primer->mock( 'seq_region', sub { return '5' } );
    $mock_left_primer->mock( 'seq_region_start', sub { return 101 } );
    $mock_left_primer->mock( 'seq_region_end', sub { return 124 } );
    $mock_left_primer->mock( 'seq_region_strand', sub { return '1' } );
    $mock_left_primer->mock( 'tail', sub { return undef } );
    $mock_left_primer->set_isa('Crispr::Primer');
    $mock_left_primer->mock('primer_id', sub { return 1 } );
    $mock_left_primer->mock( 'primer_name', sub { return '5:101-124:1' } );
    
    my $mock_right_primer = Test::MockObject->new();
    $mock_right_primer->mock( 'sequence', sub { return 'GATAGATACGATAGATGGGAC' } );
    $mock_right_primer->mock( 'seq_region', sub { return '5' } );
    $mock_right_primer->mock( 'seq_region_start', sub { return 600 } );
    $mock_right_primer->mock( 'seq_region_end', sub { return 623 } );
    $mock_right_primer->mock( 'seq_region_strand', sub { return '-1' } );
    $mock_right_primer->mock( 'tail', sub { return undef } );
    $mock_right_primer->set_isa('Crispr::Primer');
    $mock_right_primer->mock('primer_id', sub { return 2 } );
    $mock_right_primer->mock( 'primer_name', sub { return '5:600-623:-1' } );
    
    $statement = "insert into primer values( ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    foreach my $primer ( $mock_left_primer, $mock_right_primer ){
        $sth->execute(
            $primer->primer_id,
            $primer->sequence,
            $primer->seq_region,
            $primer->seq_region_start,
            $primer->seq_region_end,
            $primer->seq_region_strand,
            $primer->tail,
            undef, undef,
        );
    }
    
    my $mock_primer_pair = Test::MockObject->new();
    $mock_primer_pair->mock( 'type', sub{ return 'int-illumina_tailed' } );
    $mock_primer_pair->mock( 'left_primer', sub{ return $mock_left_primer } );
    $mock_primer_pair->mock( 'right_primer', sub{ return $mock_right_primer } );
    $mock_primer_pair->mock( 'seq_region', sub{ return $mock_left_primer->seq_region } );
    $mock_primer_pair->mock( 'seq_region_start', sub{ return $mock_left_primer->seq_region_start } );
    $mock_primer_pair->mock( 'seq_region_end', sub{ return $mock_right_primer->seq_region_end } );
    $mock_primer_pair->mock( 'seq_region_strand', sub{ return 1 } );
    $mock_primer_pair->mock( 'product_size', sub{ return 523 } );
    $mock_primer_pair->set_isa('Crispr::PrimerPair');
    $mock_primer_pair->mock('primer_pair_id', sub { return 1 } );
    
    $statement = "insert into primer_pair values( ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute(
        $mock_primer_pair->primer_pair_id,
        $mock_primer_pair->type,
        $mock_primer_pair->left_primer->primer_id,
        $mock_primer_pair->right_primer->primer_id,
        $mock_primer_pair->seq_region,
        $mock_primer_pair->seq_region_start,
        $mock_primer_pair->seq_region_end,
        $mock_primer_pair->seq_region_strand,
        $mock_primer_pair->product_size,
    );
    
    $statement = "insert into amplicon_to_crRNA values( ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute(
        $mock_primer_pair->primer_pair_id,
        $mock_crRNA_object_1->crRNA_id,
    );
    $sth->execute(
        $mock_primer_pair->primer_pair_id,
        $mock_crRNA_object_2->crRNA_id,
    );
    
    my $plate_number = 1;
    my ( $barcode_id_1, $well_id_1 ) = ( 1, 'A01' );
    my ( $barcode_id_2, $well_id_2 ) = ( 1, 'A02' );
    
    my $mock_sample_amplicon_1 = Test::MockObject->new();
    $mock_sample_amplicon_1->set_isa( 'Crispr::DB::SampleAmplicon' );
    my $analysis_id = 1;
    $mock_sample_amplicon_1->mock( 'analysis_id', sub { return $analysis_id; } );
    $mock_sample_amplicon_1->mock( 'sample', sub { return $mock_sample_1; } );
    $mock_sample_amplicon_1->mock( 'amplicons', sub { return [ $mock_primer_pair ]; } );
    $mock_sample_amplicon_1->mock( 'barcode_id', sub { return $barcode_id_1; } );
    $mock_sample_amplicon_1->mock( 'plate_number', sub { return $plate_number; } );
    $mock_sample_amplicon_1->mock( 'well_id', sub { return $well_id_1; } );
    $mock_sample_amplicon_1->mock( 'samples', sub { return ( $mock_sample_1, ); } );
    
    my $mock_sample_amplicon_2 = Test::MockObject->new();
    $mock_sample_amplicon_2->set_isa( 'Crispr::DB::SampleAmplicon' );
    $mock_sample_amplicon_2->mock( 'analysis_id', sub { return $analysis_id; } );
    $mock_sample_amplicon_2->mock( 'sample', sub { return $mock_sample_2; } );
    $mock_sample_amplicon_2->mock( 'amplicons', sub { return [ $mock_primer_pair ]; } );
    $mock_sample_amplicon_2->mock( 'barcode_id', sub { return $barcode_id_2; } );
    $mock_sample_amplicon_2->mock( 'plate_number', sub { return $plate_number; } );
    $mock_sample_amplicon_2->mock( 'well_id', sub { return $well_id_2; } );
    $mock_sample_amplicon_2->mock( 'samples', sub { return ( $mock_sample_1, ); } );
    
    my $mock_analysis = Test::MockObject->new();
    $mock_analysis->set_isa( 'Crispr::DB::SampleAmplicon' );
    $mock_analysis->mock( 'db_id', sub{ return $analysis_id; } );
    $mock_analysis->mock( 'plex', sub{ return $mock_plex } );
    $mock_analysis->mock( 'info', sub{ return [ $mock_sample_amplicon_1, $mock_sample_amplicon_2 ] } );
    $mock_analysis->mock( 'analysis_started', sub{ return '2015-02-10' } );
    $mock_analysis->mock( 'analysis_finished', sub{ return '2015-02-17' } );
    $mock_analysis->mock( 'samples', sub{ return ( $mock_sample_1, $mock_sample_2 ) } );
    $mock_analysis->mock( 'amplicons', sub{ return ( $mock_primer_pair ) } );
    
    $statement = "insert into analysis values( ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute(
        $mock_analysis->db_id,
        $mock_analysis->plex->db_id,
        $mock_analysis->analysis_started,
        $mock_analysis->analysis_finished,
    );
    
    # make a new real SampleAmplicon Adaptor
    my $sample_amplicon_adaptor = Crispr::DB::SampleAmpliconAdaptor->new( db_connection => $db_conn, );
    # 1 test
    isa_ok( $sample_amplicon_adaptor, 'Crispr::DB::SampleAmpliconAdaptor', "$driver: check object class is ok" );
    
    # check attributes and methods exist 5 + 11 tests
    foreach my $attribute ( @attributes ) {
        can_ok( $sample_amplicon_adaptor, $attribute );
    }
    foreach my $method ( @methods ) {
        can_ok( $sample_amplicon_adaptor, $method );
    }
    
    # check db adaptor attributes - 4 tests
    my $plex_adaptor;
    ok( $plex_adaptor = $sample_amplicon_adaptor->plex_adaptor(), "$driver: get plex_adaptor" );
    isa_ok( $plex_adaptor, 'Crispr::DB::PlexAdaptor', "$driver: check plex_adaptor class" );
    my $sample_adaptor;
    ok( $sample_adaptor = $sample_amplicon_adaptor->sample_adaptor(), "$driver: get sample_adaptor" );
    isa_ok( $sample_adaptor, 'Crispr::DB::SampleAdaptor', "$driver: check sample_adaptor class" );
    
    # check store methods 4 tests
    ok( $sample_amplicon_adaptor->store( $mock_sample_amplicon_1 ), "$driver: store" );
    my @rows;
    row_ok(
       table => 'analysis_information',
       where => [ analysis_id => 1 ],
       tests => {
           '==' => {
                sample_id => $mock_sample_amplicon_1->sample->db_id,
                primer_pair_id => $mock_sample_amplicon_1->amplicons->[0]->primer_pair_id,
                barcode_id => $mock_sample_amplicon_1->barcode_id,
                plate_number => $mock_sample_amplicon_1->plate_number,
           },
           'eq' => {
                well_id => $mock_sample_amplicon_1->well_id,
           },
       },
       label => "$driver: sample_amplicon stored",
    );
    
    # test that store throws properly
    throws_ok { $sample_amplicon_adaptor->store_sample_amplicon('SampleAmplicon') }
        qr/Argument\smust\sbe\sa\sCrispr::DB::SampleAmplicon\sobject/,
        "$driver: store_sample_amplicon throws on string input";
    throws_ok { $sample_amplicon_adaptor->store_sample_amplicon($mock_cas9_object) }
        qr/Argument\smust\sbe\sa\sCrispr::DB::SampleAmplicon\sobject/,
        "$driver: store_sample_amplicon throws if object is not Crispr::DB::SampleAmplicon";
    
    # store sample_amplicon - 4 tests
    ok( $sample_amplicon_adaptor->store_sample_amplicon( $mock_sample_amplicon_2 ), "$driver: store_sample_amplicon" );
    row_ok(
       table => 'analysis_information',
       where => { '=' => { analysis_id => 1,
                           sample_id => 2,
                          } },
       tests => {
           '==' => {
                sample_id => $mock_sample_amplicon_2->sample->db_id,
                primer_pair_id => $mock_sample_amplicon_2->amplicons->[0]->primer_pair_id,
                barcode_id => $mock_sample_amplicon_2->barcode_id,
                plate_number => $mock_sample_amplicon_2->plate_number,
           },
           'eq' => {
                well_id => $mock_sample_amplicon_2->well_id,
           },
       },
       label => "$driver: sample_amplicon stored",
    );
    
    throws_ok { $sample_amplicon_adaptor->store_sample_amplicons('SampleAmpliconObject') }
        qr/Supplied\sargument\smust\sbe\san\sArrayRef\sof\sSampleAmplicon\sobjects/,
        "$driver: store_sample_amplicons throws on non ARRAYREF";
    throws_ok { $sample_amplicon_adaptor->store_sample_amplicons( [ 'SampleAmpliconObject' ] ) }
        qr/Argument\smust\sbe\sa\sCrispr::DB::SampleAmplicon\sobject/,
        "$driver: store_sample_amplicons throws on string input";
    
    # increment mock object 1's id and add new analysis
    $analysis_id = 2;
    $statement = "insert into analysis values( ?, ?, ?, ? );";
    $sth = $dbh->prepare($statement);
    $sth->execute(
        $mock_analysis->db_id,
        $mock_analysis->plex->db_id,
        $mock_analysis->analysis_started,
        $mock_analysis->analysis_finished,
    );
    
    # 3 tests
    ok( $sample_amplicon_adaptor->store_sample_amplicons( [ $mock_sample_amplicon_1, $mock_sample_amplicon_2 ] ), "$driver: store_sample_amplicons" );
    row_ok(
       table => 'analysis_information',
       where => { '=' => { analysis_id => 2,
                           sample_id => 1,}
                },
       tests => {
           '==' => {
                sample_id => $mock_sample_amplicon_1->sample->db_id,
                primer_pair_id => $mock_sample_amplicon_1->amplicons->[0]->primer_pair_id,
                barcode_id => $mock_sample_amplicon_1->barcode_id,
                plate_number => $mock_sample_amplicon_1->plate_number,
           },
           'eq' => {
                well_id => $mock_sample_amplicon_1->well_id,
           },
       },
       label => "$driver: sample_amplicon stored",
    );
    row_ok(
       table => 'analysis_information',
       where => { '=' => { analysis_id => 2,
                           sample_id => 2,
                          } },
       tests => {
           '==' => {
                sample_id => $mock_sample_amplicon_2->sample->db_id,
                primer_pair_id => $mock_sample_amplicon_2->amplicons->[0]->primer_pair_id,
                barcode_id => $mock_sample_amplicon_2->barcode_id,
                plate_number => $mock_sample_amplicon_2->plate_number,
           },
           'eq' => {
                well_id => $mock_sample_amplicon_2->well_id,
           },
       },
       label => "$driver: sample_amplicon stored",
    );
    
    ## 1 test
    #throws_ok{ $sample_amplicon_adaptor->fetch_by_id( 10 ) } qr/Couldn't retrieve sample_amplicon/, 'SampleAmplicon does not exist in db';
    
    # _fetch - 5 tests
    my $sample_amplicon_from_db = @{ $sample_amplicon_adaptor->_fetch( 'sample_id = ? and primer_pair_id = ?', [ 1, 1 ] ) }[0];
    check_attributes( $sample_amplicon_from_db, $mock_sample_amplicon_1, $driver, '_fetch', );
#    
#    # fetch_by_id - 24 tests
#    $sample_amplicon_from_db = $sample_amplicon_adaptor->fetch_by_id( 4 );
#    check_attributes( $sample_amplicon_from_db, $mock_sample_amplicon_2, $driver, 'fetch_by_id', );
#    
#    # fetch_by_id - 48 tests
#    my @ids = ( 3, 4 );
#    my $inj_pools_from_db = $sample_amplicon_adaptor->fetch_by_ids( \@ids );
#    
#    my @sample_amplicons = ( $mock_sample_amplicon, $mock_sample_amplicon_2 );
#    foreach my $i ( 0..1 ){
#        my $sample_amplicon_from_db = $inj_pools_from_db->[$i];
#        my $mock_inj_pool = $sample_amplicons[$i];
#        check_attributes( $sample_amplicon_from_db, $mock_inj_pool, $driver, 'fetch_by_ids', );
#    }
#
#    # fetch_by_name - 25 tests
#    ok( $sample_amplicon_from_db = $sample_amplicon_adaptor->fetch_by_name( '172' ), 'fetch_by_name');
#    check_attributes( $sample_amplicon_from_db, $mock_sample_amplicon, $driver, 'fetch_by_name', );
#
#    # 2 tests
#    ok( $sample_amplicon_adaptor->fetch_all_by_date( '2014-10-13' ), 'fetch_all_by_date');
#TODO: {
#    local $TODO = 'methods not implemented yet.';
#    
#    ok( $sample_amplicon_adaptor->delete_sample_amplicon_from_db ( 'rna' ), 'delete_sample_amplicon_from_db');
#
#}
    $db_connection->destroy();
}

# 5 tests
sub check_attributes {
    my ( $object1, $object2, $driver, $method ) = @_;
    is( $object1->analysis_id, $object2->analysis_id, "$driver: object from db $method - check sample->db_id");
    is( $object1->sample->db_id, $object2->sample->db_id, "$driver: object from db $method - check barcode_id");
    is( $object1->barcode_id, $object2->barcode_id, "$driver: object from db $method - check plate_number");
    is( $object1->plate_number, $object2->plate_number, "$driver: object from db $method - check well_id");
    is( $object1->well_id, $object2->well_id, "$driver: object from db $method - check well_id");
}

