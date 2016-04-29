#!/usr/bin/env perl
# crRNA_adaptor.t
use warnings;
use strict;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::DatabaseRow;
use Test::MockObject;
use Data::Dumper;
use File::Slurp;
use File::Spec;
use autodie qw(:all);
use Getopt::Long;
use List::MoreUtils qw( any );
use Readonly;
use English qw( -no_match_vars );
use DateTime;
my $date = DateTime->now()->ymd;

#my $test_data = File::Spec->catfile( 't', 'data', 'test_targets_plus_crRNAs_plus_coding_scores.txt' );

#GetOptions(
#    'data=s' => \$test_data,
#);

#my $count_output = qx/wc -l $test_data/;
#chomp $count_output;
#$count_output =~ s/\s$test_data//mxs;
#
#my $cmd = "grep -oE 'ENSDART[0-9]+' $test_data | wc -l";
#my $transcript_count = qx/$cmd/;
#chomp $transcript_count;

# Number of tests
Readonly my $TESTS_IN_COMMON => 1 + 23 + 2 + 4 + 14 + 9 + 9 + 9 + 9 + 9 + 19 + 11 + 17 + 10 + 1;
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

use Crispr::DB::crRNAAdaptor;
use Crispr::DB::DBConnection;

##  database tests  ##
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

Readonly my @rows => ( qw{ A B C D E F G H } );
Readonly my @cols => ( qw{ 01 02 03 04 05 06 07 08 09 10 11 12 } );

foreach my $db_connection ( @{$db_connections} ){
    my $driver = $db_connection->driver;
    my $dbh = $db_connection->connection->dbh;
    # $dbh is a DBI database handle
    local $Test::DatabaseRow::dbh = $dbh;
    
    # make a real DBConnection object
    my $db_conn = Crispr::DB::DBConnection->new( $db_connection_params->{$driver} );
    
    # make a new real crRNA Adaptor
    my $crRNA_adaptor = Crispr::DB::crRNAAdaptor->new(db_connection => $db_conn,);
    # 1 test
    isa_ok( $crRNA_adaptor, 'Crispr::DB::crRNAAdaptor', "$driver: check object class is ok" );
    
    # check method calls 23 tests
    my @methods = qw(
        target_adaptor store store_restriction_enzyme_info store_coding_scores store_off_target_info
        store_expression_construct_info store_construction_oligos check_plasmid_backbone_exists update_status fetch_by_id
        fetch_by_ids fetch_all_by_name fetch_by_name_and_target fetch_by_names_and_targets fetch_all_by_target
        fetch_all_by_targets fetch_by_plate_num_and_well fetch_all_by_primer_pair fetch_all_by_status _fetch
        _make_new_crRNA_from_db delete_crRNA_from_db _build_target_adaptor
    );
    
    foreach my $method ( @methods ) {
        can_ok( $crRNA_adaptor, $method );
    }
    
    # check adaptors - 2 tests
    my $target_adaptor = $crRNA_adaptor->target_adaptor();
    is( $target_adaptor->db_connection, $db_conn, 'check target adaptor' );
    my $plate_adaptor = $crRNA_adaptor->plate_adaptor();
    is( $plate_adaptor->db_connection, $db_conn, 'check plate adaptor' );
    
    # mock objects
    my $args = {
        add_to_db => 1,
    };
    my ( $mock_plex, $mock_plex_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'plex', $args, $db_connection, );
    my ( $mock_cas9, $mock_cas9_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'cas9', $args, $db_connection, );
    $args->{mock_cas9_object} = $mock_cas9;
    my ( $mock_cas9_prep, $mock_cas9_prep_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'cas9_prep', $args, $db_connection, );
    my ( $mock_target, $mock_target_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'target', $args, $db_connection, );
    my ( $mock_plate, $mock_plate_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'plate', $args, $db_connection, );
    $args->{mock_plate} = $mock_plate;
    my ( $mock_well, $mock_well_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'well', $args, $db_connection, );
    $args->{mock_well} = $mock_well;
    $args->{mock_target} = $mock_target;
    $args->{add_to_db} = 0;
    $args->{crRNA_num} = 1;
    my ( $mock_crRNA_1, $mock_crRNA_1_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'crRNA', $args, $db_connection, );
    $args->{crRNA_num} = 2;
    my ( $mock_crRNA_2, $mock_crRNA_2_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'crRNA', $args, $db_connection, );
    
    # check store method - 4 tests
    $mock_well->mock('contents', sub { return $mock_crRNA_1 } );
    ok( $crRNA_adaptor->store( $mock_well ), 'store mock crRNA 1');
    $mock_well->mock('contents', sub { return $mock_crRNA_2 } );
    $mock_well->mock('position', sub { return 'A02' } );
    ok( $crRNA_adaptor->store( $mock_well ), 'store mock crRNA 2');
    
    # check fetch_status_for_crispr
    is( $crRNA_adaptor->fetch_status_for_crispr($mock_crRNA_1), $mock_crRNA_1->status, "$driver: check fetch_status_for_crispr 1" );
    is( $crRNA_adaptor->fetch_status_for_crispr($mock_crRNA_2), $mock_crRNA_2->status, "$driver: check fetch_status_for_crispr 2" );
    
    # OffTarget objects
    my $mock_exon_off_target = Test::MockObject->new();
    $mock_exon_off_target->set_isa( 'Crispr::OffTarget' );
    $mock_exon_off_target->mock( 'position', sub{ return 'test_chr1:201-223:1' });
    $mock_exon_off_target->mock( 'mismatches', sub{ return 2 });
    $mock_exon_off_target->mock( 'annotation', sub{ return 'exon' });
    
    my $mock_intron_off_target = Test::MockObject->new();
    $mock_intron_off_target->set_isa( 'Crispr::OffTarget' );
    $mock_intron_off_target->mock( 'position', sub{ return 'test_chr2:201-223:1' });
    $mock_intron_off_target->mock( 'mismatches', sub{ return 3 });
    $mock_intron_off_target->mock( 'annotation', sub{ return 'intron' });
    
    my $mock_nongenic_off_target = Test::MockObject->new();
    $mock_nongenic_off_target->set_isa( 'Crispr::OffTarget' );
    $mock_nongenic_off_target->mock( 'position', sub{ return 'test_chr1:1-23:1' });
    $mock_nongenic_off_target->mock( 'mismatches', sub{ return 1 });
    $mock_nongenic_off_target->mock( 'annotation', sub{ return 'nongenic' });
    
    my $mock_off_target_info = Test::MockObject->new();
    $mock_off_target_info->set_isa('Crispr::OffTargetInfo');
    $mock_off_target_info->mock( '_off_targets',
        sub{
            return {
                exon => [ $mock_exon_off_target ],
                intron => [ $mock_intron_off_target ],
                nongenic => [ $mock_nongenic_off_target ],
            };
        }
    );
    
    $mock_off_target_info->mock( 'all_off_targets',
        sub{
            return ( $mock_exon_off_target,
                    $mock_intron_off_target,
                    $mock_nongenic_off_target,
                );
        }
    );
    $mock_off_target_info->mock( 'number_hits', sub { return 3 } );
    $mock_crRNA_1->mock( 'off_target_hits', sub{ return $mock_off_target_info } );
    
    # store off-target - 14 tests
    ok( $crRNA_adaptor->store_off_target_info( $mock_crRNA_1 ), 'store off target info');
    
    my @rows;
    row_ok(
        sql => "SELECT * FROM off_target_info WHERE crRNA_id = 1;",
        store_rows => \@rows,
        label => "off_target_info stored - $driver: 1",
    );
    my @expected_results = (
        [ 1, 'test_chr1:1-23:1', 1, 'nongenic' ],
        [ 1, 'test_chr1:201-223:1', 2, 'exon' ],
        [ 1, 'test_chr2:201-223:1', 3, 'intron' ],
    );
    foreach my $row ( @rows ){
        my $ex = shift @expected_results;
        is( $row->{crRNA_id}, $ex->[0], "$driver: off_target_info check crRNA_id" );
        is( $row->{off_target_hit}, $ex->[1], "$driver: off_target_info check off_target_hit" );
        is( $row->{mismatches}, $ex->[2], "$driver: off_target_info check mismatches" );
        is( $row->{annotation}, $ex->[3], "$driver: off_target_info check annotation" );
    }
    
    $args->{add_to_db} = 1;
    $args->{mock_plate} = $mock_plate;
    $args->{mock_crRNA} = $mock_crRNA_1;
    $args->{gRNA_num} = 1;
    my ( $mock_gRNA_1, $mock_gRNA_1_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'gRNA', $args, $db_connection, );
    $args->{mock_crRNA} = $mock_crRNA_2;
    $args->{gRNA_num} = 2;
    my ( $mock_gRNA_2, $mock_gRNA_2_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'gRNA', $args, $db_connection, );
    $args->{mock_cas9_prep} = $mock_cas9_prep;
    $args->{mock_gRNA_1} = $mock_gRNA_1;
    $args->{mock_gRNA_2} = $mock_gRNA_2;
    my ( $mock_injection_pool, $mock_injection_pool_id, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'injection_pool', $args, $db_connection, );
    $args->{mock_injection_pool} = $mock_injection_pool;
    $args->{sample_ids} = [ 1..10 ];
    $args->{well_ids} = [ qw{A01 A02 A03 A04 A05 A06 A07 A08 A09 A10} ];
    my ( $mock_embryo_samples, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'sample', $args, $db_connection, );
    $args->{sample_ids} = [ 11..20 ];
    $args->{well_ids} = [ qw{B01 B02 B03 B04 B05 B06 B07 B08 B09 B10} ];
    $args->{samples}{type} = 'sperm';
    my ( $mock_sperm_samples, ) =
        $test_method_obj->create_mock_object_and_add_to_db( 'sample', $args, $db_connection, );
    $args->{sample_ids} = [ 1..20 ];
    $args->{well_ids} = [ qw{A01 A02 A03 A04 A05 A06 A07 A08 A09 A10 B01 B02 B03 B04 B05 B06 B07 B08 B09 B10} ];
    my $mock_samples = [ @{$mock_embryo_samples}, @{$mock_sperm_samples} ];

    # test _fetch - 9 tests
    my $crRNAs_tmp;
    ok($crRNAs_tmp = $crRNA_adaptor->_fetch( 'crRNA_id = ?', [ 1 ], ), "$driver: test _fetch method" );
    check_attributes( $crRNAs_tmp->[0], $mock_crRNA_1, $driver, '_fetch' );

    # test fetch_by_id - 9 tests
    my $crRNA_tmp;
    ok($crRNA_tmp = $crRNA_adaptor->fetch_by_id( 1, ), "$driver: test fetch_by_id method" );
    check_attributes( $crRNA_tmp, $mock_crRNA_1, $driver, 'fetch_by_id' );
    
    # test fetch_all_by_name - 9 tests
    ok($crRNAs_tmp = $crRNA_adaptor->fetch_all_by_name( 'crRNA:test_chr1:101-123:1', ), "$driver: test fetch_all_by_name method" );
    check_attributes( $crRNAs_tmp->[0], $mock_crRNA_1, $driver, 'fetch_all_by_name' );

    # test fetch_by_name_and_target - 9 tests
    ok($crRNA_tmp = $crRNA_adaptor->fetch_by_name_and_target( 'crRNA:test_chr1:101-123:1', $mock_target ), "$driver: test fetch_by_name_and_target method" );
    check_attributes( $crRNA_tmp, $mock_crRNA_1, $driver, 'fetch_by_name_and_target' );

    # test fetch_all_by_target - 9 tests
    ok($crRNAs_tmp = $crRNA_adaptor->fetch_all_by_target( $mock_target, ), "$driver: test fetch_all_by_target method" );
    check_attributes( $crRNAs_tmp->[0], $mock_crRNA_1, $driver, 'fetch_all_by_target' );
    
    # test fetch_by_plate_num_and_well - 19 tests
    ok($crRNAs_tmp = $crRNA_adaptor->fetch_by_plate_num_and_well( 1, ), "$driver: test fetch_by_plate_num_and_well method" );
    is( scalar @{$crRNAs_tmp}, 2, "$driver: fetch_by_plate_num_and_well - check number returned" );
    check_attributes( $crRNAs_tmp->[0], $mock_crRNA_1, $driver, 'fetch_by_plate_num_and_well' );
    
    ok($crRNA_tmp = $crRNA_adaptor->fetch_by_plate_num_and_well( 1, 'A01' ), "$driver: test fetch_by_plate_num_and_well method" );
    check_attributes( $crRNA_tmp, $mock_crRNA_1, $driver, 'fetch_by_plate_num_and_well' );

    # test fetch_all_by_status - 11 tests
    ok($crRNAs_tmp = $crRNA_adaptor->fetch_all_by_status( 'DESIGNED', ), "$driver: test fetch_all_by_status method" );
    is( scalar @{$crRNAs_tmp}, 1, "$driver: fetch_all_by_status method - check number returned" );
    ok($crRNAs_tmp = $crRNA_adaptor->fetch_all_by_status( 'FAILED_SPERM_SCREENING', ), "$driver: test fetch_all_by_status method" );
    check_attributes( $crRNAs_tmp->[0], $mock_crRNA_2, $driver, 'fetch_all_by_status' );
    
    # test update status - 17 tests
    throws_ok{ $crRNA_adaptor->update_status() }
        qr/A crRNA object must be supplied/,
        "$driver: check update_status throws on no input";
    throws_ok{ $crRNA_adaptor->update_status( $mock_target ) }
        qr/The supplied arguments must be a Crispr::crRNA/,
        "$driver: check update_status throws on not Crispr::crRNA object";
    
    # change status of object
    $mock_crRNA_1->mock( 'status', sub { return 'PASSED_EMBRYO_SCREENING' } );
    ok( $crRNA_adaptor->update_status( $mock_crRNA_1 ), "$driver: test update_status" );
    row_ok(
        sql => "SELECT * FROM crRNA WHERE crRNA_id = 1",
        tests => {
            'eq' => {
                status_changed => $date,
            },
            '==' => {
                status_id => 7,
            },
        },
        label => "$driver: status changed in db",
    );
    # try updating status to something that comes before the current status
    $mock_crRNA_2->mock( 'status', sub { return 'INJECTED' } );
    is( $crRNA_adaptor->update_status( $mock_crRNA_2 ), '', "$driver: test update_status with earlier status" );
    row_ok(
        sql => "SELECT * FROM crRNA WHERE crRNA_id = 2",
        tests => {
            '==' => {
                status_id => 12,
            },
        },
        label => "$driver: status unchanged in db",
    );
    # reset status
    $mock_crRNA_2->mock( 'status', sub { return 'FAILED_SPERM_SCREENING' } );
    
    ok($crRNAs_tmp = $crRNA_adaptor->fetch_all_by_status( 'DESIGNED', ), "$driver: check there are no longer crRNAs with DESIGNED status" );
    is( scalar @{$crRNAs_tmp}, 0, "$driver: check there are no longer crRNAs with DESIGNED status 2" );
    ok($crRNAs_tmp = $crRNA_adaptor->fetch_all_by_status( 'PASSED_EMBRYO_SCREENING', ), "$driver: check status changed successfully" );
    check_attributes( $crRNAs_tmp->[0], $mock_crRNA_1, $driver, "$driver: check status changed successfully" );
    
    # make mock primer and primer pair objects
    my $mock_left_primer = Test::MockObject->new();
    my $l_p_id = 1;
    $mock_left_primer->mock( 'sequence', sub { return 'CGACAGTAGACAGTTAGACGAG' } );
    $mock_left_primer->mock( 'seq_region', sub { return '5' } );
    $mock_left_primer->mock( 'seq_region_start', sub { return 101 } );
    $mock_left_primer->mock( 'seq_region_end', sub { return 124 } );
    $mock_left_primer->mock( 'seq_region_strand', sub { return '1' } );
    $mock_left_primer->mock( 'tail', sub { return undef } );
    $mock_left_primer->set_isa('Crispr::Primer');
    $mock_left_primer->mock( 'primer_id', sub { my @args = @_; if( $_[1]){ return $_[1] }else{ return $l_p_id} } );
    $mock_left_primer->mock( 'primer_name', sub { return '5:101-124:1' } );
    $mock_left_primer->mock( 'well_id', sub { return 'A01' } );
    
    my $mock_right_primer = Test::MockObject->new();
    my $r_p_id = 2;
    $mock_right_primer->mock( 'sequence', sub { return 'GATAGATACGATAGATGGGAC' } );
    $mock_right_primer->mock( 'seq_region', sub { return '5' } );
    $mock_right_primer->mock( 'seq_region_start', sub { return 600 } );
    $mock_right_primer->mock( 'seq_region_end', sub { return 623 } );
    $mock_right_primer->mock( 'seq_region_strand', sub { return '-1' } );
    $mock_right_primer->mock( 'tail', sub { return undef } );
    $mock_right_primer->set_isa('Crispr::Primer');
    $mock_right_primer->mock('primer_id', sub { my @args = @_; if( $_[1]){ return $_[1] }else{ return $r_p_id} } );
    $mock_right_primer->mock( 'primer_name', sub { return '5:600-623:-1' } );
    $mock_right_primer->mock( 'well_id', sub { return 'A01' } );
    
    # add primers and primer pair direct to db
    my $p_insert_st = 'insert into primer values( ?, ?, ?, ?, ?, ?, ?, ?, ? );';
    my $sth = $dbh->prepare( $p_insert_st );
    foreach my $p ( $mock_left_primer, $mock_right_primer ){
        $sth->execute(
            $p->primer_id, $p->sequence, $p->seq_region, $p->seq_region_start,
            $p->seq_region_end, $p->seq_region_strand, undef,
            undef, undef
        );
    }
    
    my $mock_primer_pair = Test::MockObject->new();
    my $pair_id = 1;
    $mock_primer_pair->mock( 'type', sub{ return 'ext' } );
    $mock_primer_pair->mock( 'left_primer', sub{ return $mock_left_primer } );
    $mock_primer_pair->mock( 'right_primer', sub{ return $mock_right_primer } );
    $mock_primer_pair->mock( 'seq_region', sub{ return $mock_left_primer->seq_region } );
    $mock_primer_pair->mock( 'seq_region_start', sub{ return $mock_left_primer->seq_region_start } );
    $mock_primer_pair->mock( 'seq_region_end', sub{ return $mock_right_primer->seq_region_end } );
    $mock_primer_pair->mock( 'seq_region_strand', sub{ return 1 } );
    $mock_primer_pair->mock( 'product_size', sub{ return 523 } );
    $mock_primer_pair->set_isa('Crispr::PrimerPair');
    $mock_primer_pair->mock('primer_pair_id', sub { my @args = @_; if($_[1]){ return $_[1] }else{ return $pair_id} } );
    $mock_primer_pair->mock('pair_name', sub { return '5:101-623:1' } );
    
    my $pp_insert_st = 'insert into primer_pair values( ?, ?, ?, ?, ?, ?, ?, ?, ? );';
    $sth = $dbh->prepare( $pp_insert_st );
    $sth->execute(
        $mock_primer_pair->primer_pair_id, $mock_primer_pair->type,
        $mock_primer_pair->left_primer->primer_id, $mock_primer_pair->right_primer->primer_id,
        $mock_primer_pair->seq_region, $mock_primer_pair->seq_region_start, $mock_primer_pair->seq_region_end,
        $mock_primer_pair->seq_region_strand, $mock_primer_pair->product_size,
    );
    
    # add primer_pair and crispr to amplicon_to_crRNA table
    my $amp_st = 'insert into amplicon_to_crRNA values( ?, ? );';
    $sth = $dbh->prepare( $amp_st );
    $sth->execute(
        $mock_primer_pair->primer_pair_id,
        $mock_crRNA_1->crRNA_id,
    );
    
    # test fetch_all_by_primer_pair - 10 test
    $pair_id = undef;
    throws_ok { $crRNA_adaptor->fetch_all_by_primer_pair( $mock_primer_pair ) }
        qr/primer_pair_id attribute is not defined/,
        "$driver: check fetch_all_by_primer_pair throws when there is no primer_pair_id";
    $pair_id = 1;
    ok( my $crRNAs_from_db = $crRNA_adaptor->fetch_all_by_primer_pair( $mock_primer_pair ), "$driver: fetch_all_by_primer_pair" );
    check_attributes( $crRNAs_from_db->[0], $mock_crRNA_1, $driver, 'fetch_all_by_primer_pair' );

    # test aggregate seq results - 1 test
    my @seq_results = (
        [ 11, 1, 1, 5, 21.0, 12.0, 10000 ],
        [ 12, 1, 1, 5, 21.0, 12.0, 11000 ],
        [ 13, 1, 1, 5, 21.0, 12.0, 8000 ],
        [ 14, 1, 1, 5, 21.0, 12.0, 9000 ],
        [ 15, 1, 0, 1, 3.0, 3.0, 10000 ],
        [ 16, 1, 0, 2, 2.4, 1.6, 9000 ],
        [ 1, 1, 0, 2, 3.0, 2.0, 10000 ],
        [ 2, 1, 0, 3, 4.0, 2.0, 11000 ],
        [ 3, 1, 0, 4, 3.0, 2.0, 8000 ],
        [ 4, 1, 1, 5, 21.0, 12.0, 9000 ],
        [ 11, 2, 0, 0, 0, 0, 10000 ],
        [ 12, 2, 0, 1, 2.0, 2.0, 11000 ],
        [ 13, 2, 0, 2, 2.0, 1.2, 8000 ],
        [ 14, 2, 1, 5, 21.0, 12.0, 9000 ],
        [ 15, 2, 0, 1, 3.0, 3.0, 10000 ],
        [ 16, 2, 0, 2, 2.4, 1.6, 9000 ],
    );
    my $seq_statement = 'insert into sequencing_results values(?,?,?,?,?,?,?);';
    $sth = $dbh->prepare( $seq_statement );
    foreach my $results ( @seq_results ){
        $sth->execute(
            $results->[0],
            $results->[1],
            $results->[2],
            $results->[3],
            $results->[4],
            $results->[5],
            $results->[6],
        );
    }
    
    my %expected_results = (
        '1' => {
                    'embryo' => 1,
                    'sperm' => 4
                },
        '2' => {
                    'embryo' => 1
               },
    );
    ok( my $results = $crRNA_adaptor->aggregate_sequencing_results( [ $mock_crRNA_1, $mock_crRNA_2, ] ),
        'aggregate_sequencing_results');
    print Dumper( $results );
    
    # destroy database
    $db_connection->destroy();
}

sub increment {
    my ( $rowi, $coli ) = @_;
    
    $coli++;
    if( $coli > 11 ){
        $coli = 0;
        $rowi++;
    }
    if( $rowi > 7 ){
        die "more than one plate of stuff!\n";
    }
    return ( $rowi, $coli );
}

# 8 tests each call
sub check_attributes {
    my ( $obj_1, $obj_2, $driver, $method, ) = @_;
    is( $obj_1->crRNA_id, $obj_2->crRNA_id, "$driver: object from db $method - check crRNA db_id" );
    is( $obj_1->name, $obj_2->name, "$driver: object from db $method - check crRNA name" );
    is( $obj_1->sequence, $obj_2->sequence, "$driver: object from db $method - check crRNA sequence" );
    is( $obj_1->chr, $obj_2->chr, "$driver: object from db $method - check crRNA chr" );
    is( $obj_1->start, $obj_2->start, "$driver: object from db $method - check crRNA start" );
    is( $obj_1->end, $obj_2->end, "$driver: object from db $method - check crRNA end" );
    is( $obj_1->strand, $obj_2->strand, "$driver: object from db $method - check crRNA strand" );
    is( $obj_1->five_prime_Gs, $obj_2->five_prime_Gs, "$driver: object from db $method - check crRNA five_prime_Gs" );
}
