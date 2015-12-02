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

my $test_data = File::Spec->catfile( 't', 'data', 'test_targets_plus_crRNAs_plus_coding_scores.txt' );

GetOptions(
    'data=s' => \$test_data,
);

my $count_output = qx/wc -l $test_data/;
chomp $count_output;
$count_output =~ s/\s$test_data//mxs;

my $cmd = "grep -oE 'ENSDART[0-9]+' $test_data | wc -l";
my $transcript_count = qx/$cmd/;
chomp $transcript_count;

# Number of tests
Readonly my $TESTS_IN_COMMON => 1 + 16 + 2 + $count_output * 13 + 1 + $transcript_count + 2 + 13 + 1 + 15 + 10;
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
    
    # check method calls 16 tests
    my @methods = qw(
        target_adaptor store store_restriction_enzyme_info store_coding_scores store_off_target_info
        store_expression_construct_info store_construction_oligos fetch_by_id fetch_by_ids fetch_by_name_and_target
        fetch_by_names_and_targets fetch_all_by_target fetch_by_plate_num_and_well _make_new_crRNA_from_db delete_crRNA_from_db
        _build_target_adaptor
    );
    
    foreach my $method ( @methods ) {
        can_ok( $crRNA_adaptor, $method );
    }
    
    # check adaptors - 2 tests
    my $target_adaptor = $crRNA_adaptor->target_adaptor();
    is( $target_adaptor->db_connection, $db_conn, 'check target adaptor' );
    my $plate_adaptor = $crRNA_adaptor->plate_adaptor();
    is( $plate_adaptor->db_connection, $db_conn, 'check plate adaptor' );
    
    my ( $rowi, $coli ) = ( 0, 0 );
    # insert some data directly into db
    my $statement = "insert into plate values( ?, ?, ?, ?, ?, ? );";
    
    my $sth ;
    $sth = $dbh->prepare($statement);
    $sth->execute( 1, 'CR_000001-', '96', 'crispr', undef, undef, );
    $sth->execute( 2, 'CR_000001a', '96', 'cloning_oligos', undef, undef, );
    $sth->execute( 3, 'CR_000001b', '96', 'expression_construct', undef, undef, );
    $sth->execute( 4, 'CR_000001c', '96', 'expression_construct', undef, undef, );
    
    my $count = 0;
    # load data into objects
    open my $fh, '<', $test_data or die "Couldn't open file: $test_data!\n";
    
    my $cr_name;
    my $last_target_id;
    my $mock_target = Test::MockObject->new();
    $mock_target->set_isa( 'Crispr::Target' );
    my $mock_crRNA = Test::MockObject->new();
    $mock_crRNA->set_isa( 'Crispr::crRNA' );
    
    my $mock_plate = Test::MockObject->new();
    $mock_plate->set_isa( 'Crispr::Plate' );
    $mock_plate->mock('plate_id', sub { return 1 } );
    $mock_plate->mock('plate_name', sub { return 'CR_000001-' } );
    my $mock_well = Test::MockObject->new();
    $mock_well->set_isa( 'Labware::Well' );
    $mock_well->mock('contents', sub { return $mock_crRNA } );
    $mock_well->mock('plate', sub { return $mock_plate } );

    my $test_warning = 1;
    # 12 tests per crRNA
    while(<$fh>){
        $count++;
        my $well_id = $rows[ $rowi ] . $cols[ $coli ];
        chomp;
        my ( $target_id, $name, $assembly, $target_chr, $target_start, $target_end, $target_strand,
            $species, $requires_enzyme, $gene_id, $gene_name, $requestor, $ensembl_version, $designed,
            $id, $chr, $start, $end, $strand, $score, $sequence, $forward_oligo, $reverse_oligo,
            $off_target_score, $seed_score, $seed_hits, $align_score, $alignments,
            $coding_score, $coding_scores_by_transcript ) = split /\s/, $_;
        
        #my ( $seed_exon_hits, $seed_intron_hits, $seed_nongenic_hits ) = split /\//, $seed_hits;
        #my ( $exon_hits, $intron_hits, $nongenic_hits )  = split /\//, $alignments;
        #
        my $mock_off_target = Test::MockObject->new();
        $mock_off_target->set_isa( 'Crispr::OffTarget' );
        #$mock_off_target->mock('crRNA_name', sub { return $id } );
        #$mock_off_target->mock('bwa_exon_alignments', sub { return [ '5:1-23:1', '10:100-123:-1' ] } );
        #$mock_off_target->mock('number_bwa_intron_hits', sub { return 2 } );
        #$mock_off_target->mock('number_bwa_nongenic_hits', sub { return 2 } );
        #$mock_off_target->mock('number_seed_intron_hits', sub { return $seed_intron_hits } );
        #$mock_off_target->mock('number_seed_nongenic_hits', sub { return $seed_nongenic_hits } );
        #$mock_off_target->mock('number_exonerate_intron_hits', sub { return $intron_hits } );
        #$mock_off_target->mock('number_exonerate_nongenic_hits', sub { return $nongenic_hits } );
        $mock_off_target->mock('score', sub { return $off_target_score } );
        #$mock_off_target->mock('seed_score', sub { return $seed_score } );
        #$mock_off_target->mock('seed_hits', sub { return $seed_hits } );
        #$mock_off_target->mock('exonerate_score', sub { return $align_score } );
        #$mock_off_target->mock('exonerate_hits', sub { return $alignments } );
        #$mock_off_target->mock('number_bwa_exon_hits', sub { return undef } );
        
        $coding_score = $coding_score eq 'NULL' ? undef : $coding_score;
        my %coding_scores_for;
        if( $coding_scores_by_transcript ne 'NULL' ){
            foreach ( split /;/, $coding_scores_by_transcript ){
                my( $transcript, $score ) = split /=/, $_;
                $coding_scores_for{ $transcript } = $score;
            }
        }
        #print Dumper( %coding_scores_for );
        
        my %bool_for = (
            y => 1,
            n => 0,
        );
        
        my $t_id;
        $mock_target->mock('target_id', sub { my @args = @_; if( $_[1] ){ $t_id = $_[1] } return $t_id; } );
        $mock_target->mock('target_name', sub { return $gene_id } );
        $mock_target->mock('assembly', sub { return $assembly } );
        $mock_target->mock('chr', sub { return $target_chr } );
        $mock_target->mock('start', sub { return $target_start } );
        $mock_target->mock('end', sub { return $target_end } );
        $mock_target->mock('strand', sub { return $target_strand } );
        $mock_target->mock('species', sub { return $species } );
        $mock_target->mock('requires_enzyme', sub { return $bool_for{$requires_enzyme} } );
        $mock_target->mock('gene_id', sub { return $gene_id } );
        $mock_target->mock('gene_name', sub { return $gene_name } );
        $mock_target->mock('requestor', sub { return $requestor } );
        $mock_target->mock('ensembl_version', sub { return $ensembl_version } );
        $mock_target->mock('status', sub { return 'REQUESTED'; } );
        $mock_target->mock('status_changed', sub { return '2015-11-30'; } );
        
        my $c_id;        
        $mock_crRNA->mock('target', sub { return undef } );
        $mock_crRNA->mock('crRNA_id', sub { my @args = @_; if( $_[1] ){ $c_id = $_[1] } return $c_id; } );
        $mock_crRNA->mock('chr', sub { return $chr } );
        $mock_crRNA->mock('start', sub { return $start } );
        $mock_crRNA->mock('end', sub { return $end } );
        $mock_crRNA->mock('strand', sub { return $strand } );
        $mock_crRNA->mock('sequence', sub { return $sequence } );
        $mock_crRNA->mock('forward_oligo', sub { return $forward_oligo } );
        $mock_crRNA->mock('reverse_oligo', sub { return $reverse_oligo } );
        $mock_crRNA->mock('plasmid_backbone', sub { return 'pDR274' } );
        $mock_crRNA->mock('off_target_hits', sub { return $mock_off_target } );
        $mock_crRNA->mock('coding_scores', sub { return \%coding_scores_for } );
        $mock_crRNA->mock('crRNA_adaptor', sub { return $crRNA_adaptor } );
        $mock_crRNA->mock('target_id', sub { return $mock_crRNA->target->target_id } );
        $mock_crRNA->mock('target_name', sub { return $mock_target->target_name } );
        $mock_crRNA->mock('name', sub { return $id } );
        $mock_crRNA->mock('score', sub { return $score } );
        $mock_crRNA->mock('coding_score', sub { return $coding_score } );
        $mock_crRNA->mock('unique_restriction_sites', sub { return undef } );
        $mock_crRNA->mock('coding_scores', sub { return \%coding_scores_for } );
        $mock_crRNA->mock('off_target_score', sub { return $mock_off_target->score } );
        $mock_crRNA->mock('seed_score', sub { return $mock_off_target->seed_score } );
        $mock_crRNA->mock('seed_hits', sub { return $mock_off_target->seed_hits } );
        $mock_crRNA->mock('exonerate_score', sub { return $mock_off_target->exonerate_score } );
        $mock_crRNA->mock('exonerate_hits', sub { return $mock_off_target->exonerate_hits } );
        $mock_crRNA->mock('five_prime_Gs', sub { return 2 } );
        $mock_crRNA->mock('status', sub { return 'DESIGNED' } );
        $mock_crRNA->mock('status_changed', sub { return '2015-11-30'; } );
        
        $mock_well->mock('position', sub { return $well_id } );
        
        # store crRNA - 3 tests
        #check throws on no target
        throws_ok{ $crRNA_adaptor->store($mock_well) } qr/must\shave\san\sassociated\sTarget/, 'Store crRNA without target';
        my $target = $mock_target;
        $mock_crRNA->mock('target', sub { my @args = @_; if( $_[1] ){ $target = $_[1] } return $target; } );
        is($crRNA_adaptor->store($mock_well), 1, 'Store crRNA');
        is( $mock_crRNA->crRNA_id, $count, 'Check database id' );
        $t_id = $mock_crRNA->target->target_id;
        
        my %strand_for = (
            '+' => '1',
            '-' => '-1',
            1   => '1',
            -1  => '-1',
        );
        
        # check database rows - 4 tests (not including transcript test. calculated elsewhere)
        my %row;
        row_ok(
            sql => "SELECT * FROM crRNA WHERE crRNA_id = $count",
            store_row => \%row,
            tests => {
                'eq' => {
                     chr  => $chr,
                     strand => $strand_for{$strand},
                     sequence => $sequence,
                },
                '==' => {
                     start  => $start,
                     end    => $end,
                     target_id => $mock_crRNA->target_id,
                },
            },
            label => "crRNA stored - $id",
        );
        #print $row{'score'}, "\t", $score, "\t", abs($row{'score'} - $score), "\n";
        is( abs($row{'score'} - $score) < 0.002, 1, "score from db - $id" );
        #print $row{'coding_score'}, "\t", $coding_score, abs($row{'score'} - $score), "\n";
        if( !defined $coding_score ){
            is( $row{'coding_score'}, undef, "coding score from db - $id" );
        }
        else{
            is( abs($row{'coding_score'} - $coding_score) < 0.002, 1, "coding score from db - $id" );
        }
        
        # store coding scores
        my @rows;
        ok( $crRNA_adaptor->store_coding_scores( $mock_crRNA ), 'store coding scores' );
        SKIP: {
            skip 'undef coding scores', 1 if !defined $coding_score;
            row_ok(
                table => 'coding_scores',
                where => [ crRNA_id => $count ],
                store_rows => \@rows,
            );
            foreach my $row ( @rows ){
                is( $row->{'score'} - $coding_scores_for{ $row->{'transcript_id'} } < 0.002, 1, "Transcript scores from db - $id");
            }
        }
        
        # make mock well object
        $mock_plate->mock('plate_name', sub { return 'CR_000001a' } );
        
        # store construction oligos - 1 test
        if( $test_warning == 1 ){
            warning_like { $crRNA_adaptor->store_construction_oligos( $mock_well, 'cloning_oligos' ) }
                qr/Plasmid\sbackbone\spDR274\sdoesn't\sexist\sin\sthe\sdatabase\s-\sAdding/,
                "Warn if plasmid backbone doesn't exist in the db.";
            $test_warning = 0;
        }
        else{
            $crRNA_adaptor->store_construction_oligos( $mock_well, 'cloning_oligos' );
        }
        row_ok(
            sql => "SELECT * FROM construction_oligos WHERE crRNA_id = $count",
            tests => {
                'eq' => {
                     forward_oligo => $forward_oligo,
                     reverse_oligo => $reverse_oligo,
                     well_id => $well_id,
                },
                '==' => {
                    plate_id => $mock_plate->plate_id,
                },
            },
            label => "construction oligos stored - $id",
        );
        
        # store expression construct - 4 tests
        foreach my $suffix ( qw{ b c } ){
            my $plate_id = $suffix eq 'b'   ?   3   :   4;
            $mock_plate->mock('plate_id', sub { return $plate_id } );
            $mock_plate->mock('plate_name', sub { return 'CR_000001' . $suffix } );
            $crRNA_adaptor->store_expression_construct_info( $mock_well );
            
            row_ok(
                sql => "SELECT * FROM expression_construct WHERE crRNA_id = $count",
                store_rows => \@rows,
                tests => {
                    'eq' => {
                         trace_file => undef,
                         seq_verified => undef,
                         well_id => $well_id,
                    },
                    '==' => {
                        plasmid_backbone_id => 1,
                    },
                },
                label => "expression constructs stored - $id",
            );
            my @plate_ids;
            foreach my $row ( @rows ){
                push @plate_ids, $row->{'plate_id'};
            }
            is( (any { $_ == $plate_id } @plate_ids ), 1, "check expression construct plate id - $id");
        }
        $cr_name = $id;
        $last_target_id = $mock_crRNA->target_id;
        ( $rowi, $coli ) = increment( $rowi, $coli );
    }

    # check exists_in_db method - 2 tests
    is( $crRNA_adaptor->exists_in_db( $mock_crRNA->name ), 1, 'check exists_in_db - crRNA is in db' );
    is( $crRNA_adaptor->exists_in_db( 'crRNA:5:109-131:-1' ), undef, "check exists_in_db - crRNA isn't in db" );
    
    #my $crRNA_3 = $crRNA_adaptor->fetch_by_name_and_requestor( $cr_name, $target_requestor );
    $mock_target->mock('target_id', sub { return $last_target_id } );
    my $crRNA_3 = $crRNA_adaptor->fetch_by_name_and_target( $cr_name, $mock_target );
    # 13 tests
    is( $crRNA_3->crRNA_id, 13, 'Get id' );
    is( $crRNA_3->name, 'crRNA:5:75465364-75465386:-1', 'Get name' );
    is( $crRNA_3->chr, '5', 'Get chr' );
    is( $crRNA_3->start, 75465364, 'Get start' );
    is( $crRNA_3->end, 75465386, 'Get end' );
    is( $crRNA_3->strand, '-1', 'Get strand' );
    is( $crRNA_3->species, 'zebrafish', 'Get species' );
    is( $crRNA_3->target_gene_id , 'ENSDARG00000024894', 'Get gene id' );
    is( $crRNA_3->target_gene_name , 'tbx5a', 'Get gene name' );
    is( $crRNA_3->target->requestor , 'crispr_test', 'Get requestor' );
    is( $crRNA_3->target->ensembl_version , 70, 'Get version' );
    is( $crRNA_3->target->status_changed, $mock_target->status_changed, 'Get date' );
    isa_ok( $crRNA_3->crRNA_adaptor, 'Crispr::DB::crRNAAdaptor', 'check crRNA adaptor');
    
    # check fetch_by_name throws properly if crRNA is not in db
    # 1 extra test
    throws_ok { $crRNA_adaptor->fetch_by_name_and_target( 'crRNA:10:75476583-75476605:-1', $mock_target ) }
        qr/crRNA\sdoes\snot\sexist\sin\sthe\sdatabase/, 'fetch_by_name throws properly if crRNA not in db';
    
    close( $fh );
    
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
    
    $mock_target->mock('target_id', sub { return 100; } );
    $mock_target->mock('target_name', sub { return 'gene001' } );
    $mock_target->mock('assembly', sub { return 'Zv9' } );
    $mock_target->mock('chr', sub { return 'test_chr1' } );
    $mock_target->mock('start', sub { return 1 } );
    $mock_target->mock('end', sub { return 200 } );
    $mock_target->mock('strand', sub { return '1' } );
    $mock_target->mock('species', sub { return 'zebrafish' } );
    $mock_target->mock('requires_enzyme', sub { return 0 } );
    $mock_target->mock('gene_id', sub { return 'gene_001' } );
    $mock_target->mock('gene_name', sub { return 'gene1' } );
    $mock_target->mock('requestor', sub { return 'cr1' } );
    $mock_target->mock('ensembl_version', sub { return 74 } );
    $mock_target->mock('designed', sub { return undef } );

    my $mock_crRNA1 = Test::MockObject->new();
    $mock_crRNA1->set_isa( 'Crispr::crRNA' );
    $mock_crRNA1->mock( 'crRNA_id', sub{ return 100 });
    $mock_crRNA1->mock( 'name', sub{ return 'crRNA:test_chr1:101-123:1' });
    $mock_crRNA1->mock( 'chr', sub{ return 'test_chr1' });
    $mock_crRNA1->mock( 'start', sub{ return 101 });
    $mock_crRNA1->mock( 'end', sub{ return 123 });
    $mock_crRNA1->mock( 'strand', sub{ return '1' });
    $mock_crRNA1->mock( 'sequence', sub{ return 'AACTGATCGGGATCGCTATCTGG' });
    $mock_crRNA1->mock( 'off_target_hits', sub{ return $mock_off_target_info } );
    $mock_crRNA1->mock( 'cut_site', sub{ return 117 });
    $mock_crRNA1->mock( 'five_prime_Gs', sub{ return 0 });
    $mock_crRNA1->mock( 'score', sub{ return 0.5 });
    $mock_crRNA1->mock( 'off_target_score', sub{ return 0.76 });
    $mock_crRNA1->mock( 'coding_score', sub{ return 0.7 });
    $mock_crRNA1->mock( 'target', sub { return $mock_target } );
    $mock_crRNA1->mock( 'target_id', sub { return $mock_target->target_id } );
    $mock_crRNA1->mock( 'status', sub { return 'INJECTED' } );
    $mock_crRNA1->mock( 'status_changed', sub { return '2015-12-02' } );

    $mock_well->mock('contents', sub { return $mock_crRNA1 } );
    $mock_well->mock('position', sub { return 'H12' } );
    
    # add target and crRNA to db - 15 tests
    ok( $crRNA_adaptor->store( $mock_well ), 'store mock crRNA and target');
    ok( $crRNA_adaptor->store_off_target_info( $mock_crRNA1 ), 'store off target info');
    
    my @rows;
    row_ok(
        sql => "SELECT * FROM off_target_info WHERE crRNA_id = 100;",
        store_rows => \@rows,
        label => "off_target_info stored - $driver: 100",
    );
    my @expected_results = (
        [ 100, 'test_chr1:1-23:1', 1, 'nongenic' ],
        [ 100, 'test_chr1:201-223:1', 2, 'exon' ],
        [ 100, 'test_chr2:201-223:1', 3, 'intron' ],
    );
    foreach my $row ( @rows ){
        my $ex = shift @expected_results;
        is( $row->{crRNA_id}, $ex->[0], "$driver: off_target_info check crRNA_id" );
        is( $row->{off_target_hit}, $ex->[1], "$driver: off_target_info check off_target_hit" );
        is( $row->{mismatches}, $ex->[2], "$driver: off_target_info check mismatches" );
        is( $row->{annotation}, $ex->[3], "$driver: off_target_info check annotation" );
    }
    
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
    $sth = $dbh->prepare( $p_insert_st );
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
        $mock_crRNA1->crRNA_id,
    );
    
    # test fetch_all_by_primer_pair - 10 test
    $pair_id = undef;
    throws_ok { $crRNA_adaptor->fetch_all_by_primer_pair( $mock_primer_pair ) }
        qr/primer_pair_id attribute is not defined/,
        "$driver: check fetch_all_by_primer_pair throws when there is no primer_pair_id";
    $pair_id = 1;
    ok( my $crRNAs_from_db = $crRNA_adaptor->fetch_all_by_primer_pair( $mock_primer_pair ), "$driver: fetch_all_by_primer_pair" );
    check_attributes( $crRNAs_from_db->[0], $mock_crRNA1, $driver, 'fetch_all_by_primer_pair' );
    
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
