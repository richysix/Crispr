#!/usr/bin/env perl
# cprimer_pair_adaptor.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::DatabaseRow;
use Test::MockObject;
use Data::Dumper;
use autodie qw(:all);
use Getopt::Long;
use Readonly;
use File::Spec;

my $test_data = File::Spec->catfile( 't', 'data', 'test_primer_data.tsv' );

GetOptions(
    'data=s' => \$test_data,
);

my $count_output = qx/wc -l $test_data/;
chomp $count_output;
$count_output =~ s/\s$test_data//mxs;
#
#my $cmd = "grep -oE 'ENSDART[0-9]+' $test_data | wc -l";
#my $transcript_count = qx/$cmd/;
#chomp $transcript_count;
#
Readonly my $TESTS_FOREACH_DBC => 1 + 11 + $count_output * 5 + 6;
plan tests => 2 * $TESTS_FOREACH_DBC;

use Crispr::DB::DBConnection;
use Crispr::DB::PrimerPairAdaptor;
use Crispr::DB::TargetAdaptor;
use Crispr::DB::crRNAAdaptor;
use Crispr::DB::PlateAdaptor;
use Crispr::DB::PrimerAdaptor;

##  database tests  ##
# Module with a function for creating an empty test database
# and returning a database connection
use TestDB;
# check environment variables have been set
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
    skip 'No database connections available', $TESTS_FOREACH_DBC * 2 if !@db_connections;
    skip 'Only one database connection available', $TESTS_FOREACH_DBC
      if @db_connections == 1;
}

Readonly my @rows => ( qw{ A B C D E F G H } );
Readonly my @cols => ( qw{ 01 02 03 04 05 06 07 08 09 10 11 12 } );

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
    
    # make adaptors
    #my $target_ad = Crispr::DB::TargetAdaptor->new( db_connection => $mock_db_connection, );
    #my $crRNA_ad = Crispr::DB::crRNAAdaptor->new( db_connection => $mock_db_connection, );
    #my $plate_ad = Crispr::DB::PlateAdaptor->new( db_connection => $mock_db_connection, );
    #my $primer_ad = Crispr::DB::PrimerAdaptor->new( db_connection => $mock_db_connection, );
    #my $primer_pair_ad = Crispr::DB::PrimerPairAdaptor->new( db_connection => $mock_db_connection, );

    my $target_ad = Crispr::DB::TargetAdaptor->new( db_connection => $db_connection, );
    my $crRNA_ad = Crispr::DB::crRNAAdaptor->new( db_connection => $db_connection, );
    my $plate_ad = Crispr::DB::PlateAdaptor->new( db_connection => $db_connection, );
    my $primer_ad = Crispr::DB::PrimerAdaptor->new( db_connection => $db_connection, );
    my $primer_pair_ad = Crispr::DB::PrimerPairAdaptor->new( db_connection => $db_connection, );

    # 1 test
    isa_ok( $primer_pair_ad, 'Crispr::DB::PrimerPairAdaptor' );
    
    # check attributes and methods exist 3 + 8 tests
    my @attributes = ( qw{ dbname db_connection connection } );
    
    my @methods = (
        qw{ store fetch_primer_pair_by_crRNA _make_new_primer_pair_from_db _build_plate_adaptor check_entry_exists_in_db
        fetch_rows_expecting_single_row fetch_rows_for_generic_select_statement _db_error_handling }
    );

    foreach my $attribute ( @attributes ) {
        can_ok( $primer_pair_ad, $attribute );
    }
    foreach my $method ( @methods ) {
        can_ok( $primer_pair_ad, $method );
    }
    
    # make a mock Target and load it into the db
    my $mock_target = Test::MockObject->new();
    $mock_target->set_isa('Crispr::Target');
    $mock_target->mock('target_name', sub{ 'name' } );
    $mock_target->mock('assembly', sub{ 'Zv9' } );
    $mock_target->mock('chr', sub{ '5' } );
    $mock_target->mock('start', sub{ '50000' } );
    $mock_target->mock('end', sub{ '50500' } );
    $mock_target->mock('strand', sub{ '1' } );
    $mock_target->mock('species', sub{ 'zebrafish' } );
    $mock_target->mock('requires_enzyme', sub{ 'n' } );
    $mock_target->mock('gene_id', sub{ 'ENSDARG0100101' } );
    $mock_target->mock('gene_name', sub{ 'gene_name' } );
    $mock_target->mock('requestor', sub{ 'rw4' } );
    $mock_target->mock('ensembl_version', sub{ '71' } );
    $mock_target->mock('designed', sub{ '2013-08-09' } );
    $mock_target->mock('target_id', sub{ '1' } );
    $mock_target->set_isa('Crispr::Target');
    
    $target_ad->store( $mock_target );
    
    # make a mock crRNA and load it into the db
    my $mock_crRNA = Test::MockObject->new();
    $mock_crRNA->set_isa('Crispr::crRNA');
    $mock_crRNA->mock('crRNA_id', sub{ '1' } );
    $mock_crRNA->mock('name', sub{ 'crRNA:5:50383-50405:1' } );
    $mock_crRNA->mock('chr', sub{ '5' } );
    $mock_crRNA->mock('start', sub{ '50383' } );
    $mock_crRNA->mock('end', sub{ '50405' } );
    $mock_crRNA->mock('strand', sub{ '1' } );
    $mock_crRNA->mock('sequence', sub{ 'GGAATAGAGAGATAGAGAGTCGG' } );
    $mock_crRNA->mock('forward_oligo', sub{ 'ATGGGGAATAGAGAGATAGAGAGT' } );
    $mock_crRNA->mock('reverse_oligo', sub{ 'AAACACTCTCTATCTCTCTATTCC' } );
    $mock_crRNA->mock('score', sub{ '0.853' } );
    $mock_crRNA->mock('coding_score', sub{ '0.853' } );
    $mock_crRNA->mock('target_id', sub{ '1' } );
    $mock_crRNA->mock('target', sub{ return $mock_target } );
    $mock_crRNA->mock('unique_restriction_sites', sub { return undef } );
    $mock_crRNA->mock('coding_scores', sub { return undef } );
    $mock_crRNA->mock( 'off_target_score', sub { return 1 } );
    $mock_crRNA->mock( 'off_target_hits', sub { return undef } );
    $mock_crRNA->mock( 'plasmid_backbone', sub { return 'pDR274' } );
    $mock_crRNA->mock( 'primer_pairs', sub { return undef } );
    $mock_crRNA->mock( 'five_prime_Gs', sub { return 0 } );
    
    
    $crRNA_ad->store( $mock_crRNA, 1, 'A01' );
    
    my $count = 0;
    # load data into objects
    open my $fh, '<', $test_data or die "Couldn't open file: $test_data!\n";
    my ( $l_p_id, $r_p_id, $pair_id ) = ( -1, 0, 0 );
    my ( $mock_p1, $mock_p2, $mock_pp );
    while(<$fh>){
        $count++;
        chomp;
        my ( $id, $primer_type, $plate_num, $well_id, $primer_pair_id,
            $left_primer_id, $left_primer_seq, $right_primer_id, $right_primer_seq, $product_size, ) = split /\s/, $_;
        
        # make mock plate object
        my $plate_suffix = $primer_type eq 'ext'    ?   'd'
            :               $primer_type eq 'int'   ?   'e'
            :                                           'ERROR'
            ;
        my $mock_plate = Test::MockObject->new();
        $mock_plate->set_isa('Crispr::Plate');
        $mock_plate->mock('plate_id', sub { return undef } );
        $mock_plate->mock('plate_name', sub { return 'CR_00000' . $plate_num . $plate_suffix } );
        $mock_plate->mock('plate_type', sub { return '96' } );
        $mock_plate->mock('plate_category', sub { return 'pcr_primers' } );
        $mock_plate->mock('ordered', sub { return undef } );
        $mock_plate->mock('received', sub { return undef } );
        # check whether plate exists in the db, if not add it.
        my $plate_id;
        if( $plate_ad->check_entry_exists_in_db( 'select count(*) from plate where plate_name = ?;', [ $mock_plate->plate_name ] ) ){
            # fetch plate_id
            $plate_id = $plate_ad->get_plate_id_from_name( $mock_plate->plate_name );
        }
        else{
            $plate_ad->store( $mock_plate );
            $plate_id = $plate_ad->get_plate_id_from_name( $mock_plate->plate_name );
        }
        $mock_plate->mock('plate_id', sub { return $plate_id } );
        
        # make mock well object
        my $mock_well = Test::MockObject->new();
        $mock_well->set_isa('Labware::Well');
        $mock_well->mock('plate', sub { return $mock_plate } );
        $mock_well->mock('position', sub { return $well_id } );
        
        # make mock primer and primer pair objects
        my ( $l_chr, $l_region, $l_strand ) = split /:/, $left_primer_id;
        my ( $l_start, $l_end, ) = split /-/, $l_region;
        my $mock_left_primer = Test::MockObject->new();
        $l_p_id += 2;
        $mock_left_primer->mock( 'sequence', sub { return $left_primer_seq } );
        $mock_left_primer->mock( 'seq_region', sub { return $l_chr } );
        $mock_left_primer->mock( 'seq_region_start', sub { return $l_start } );
        $mock_left_primer->mock( 'seq_region_end', sub { return $l_end } );
        $mock_left_primer->mock( 'seq_region_strand', sub { return $l_strand } );
        $mock_left_primer->set_isa('Crispr::Primer');
        $mock_left_primer->mock('primer_id', sub { my @args = @_; if( $_[1]){ return $_[1] }else{ return $l_p_id} } );
        $mock_left_primer->mock( 'primer_name', sub { return $left_primer_id } );
        $mock_p1 = $mock_left_primer;
        
        my ( $r_chr, $r_region, $r_strand ) = split /:/, $right_primer_id;
        my ( $r_start, $r_end, ) = split /-/, $r_region;
        my $mock_right_primer = Test::MockObject->new();
        $r_p_id += 2;
        $mock_right_primer->mock( 'sequence', sub { return $right_primer_seq } );
        $mock_right_primer->mock( 'seq_region', sub { return $r_chr } );
        $mock_right_primer->mock( 'seq_region_start', sub { return $r_start } );
        $mock_right_primer->mock( 'seq_region_end', sub { return $r_end } );
        $mock_right_primer->mock( 'seq_region_strand', sub { return $r_strand } );
        $mock_right_primer->set_isa('Crispr::Primer');
        $mock_right_primer->mock('primer_id', sub { my @args = @_; if( $_[1]){ return $_[1] }else{ return $r_p_id} } );
        $mock_right_primer->mock( 'primer_name', sub { return $right_primer_id } );
        $mock_p2 = $mock_right_primer;
        
        my $mock_primer_pair = Test::MockObject->new();
        $pair_id++;
        my $seq_region = $mock_left_primer->seq_region;
        my $seq_region_start = $mock_left_primer->seq_region_start < $mock_right_primer->seq_region_start ?
                $mock_left_primer->seq_region_start
            :   $mock_right_primer->seq_region_start;
        my $seq_region_end = $mock_left_primer->seq_region_end > $mock_right_primer->seq_region_end ?
                $mock_left_primer->seq_region_end
            :   $mock_right_primer->seq_region_end;
        $mock_primer_pair->mock( 'type', sub{ return $primer_type } );
        $mock_primer_pair->mock( 'left_primer', sub{ return $mock_left_primer } );
        $mock_primer_pair->mock( 'right_primer', sub{ return $mock_right_primer } );
        $mock_primer_pair->mock( 'seq_region', sub{ return $seq_region } );
        $mock_primer_pair->mock( 'seq_region_start', sub{ return $seq_region_start } );
        $mock_primer_pair->mock( 'seq_region_end', sub{ return $seq_region_end } );
        $mock_primer_pair->mock( 'seq_region_strand', sub{ return 1 } );
        $mock_primer_pair->mock( 'product_size', sub{ return $product_size } );
        $mock_primer_pair->set_isa('Crispr::PrimerPair');
        $mock_primer_pair->mock('primer_pair_id', sub { my @args = @_; if($_[1]){ return $_[1] }else{ return $pair_id} } );
        $mock_pp = $mock_primer_pair;
        
        # store primer pair
        throws_ok{ $primer_pair_ad->store( $mock_primer_pair, [ $mock_crRNA ] ) }
            qr/Couldn't locate primer/, 'Try storing primer pair before primers are stored';
        
        # store left and right primer
        $mock_well->mock('contents', sub { return $mock_left_primer } );
        $primer_ad->store( $mock_well );
        $mock_well->mock('contents', sub { return $mock_right_primer } );
        $primer_ad->store( $mock_well );
        
        # now store primer pair info
        $primer_pair_ad->store( $mock_primer_pair, [ $mock_crRNA ] );
        
        # check database rows
        # 4 tests
        row_ok(
            sql => "SELECT * FROM primer_pair WHERE primer_pair_id = $count",
            tests => {
                'eq' => {
                     type  => $primer_type,
                },
                '==' => {
                     left_primer_id    => $count*2 - 1,
                     right_primer_id    => $count*2,
                     product_size => $product_size,
                },
            },
            label => "primer pair stored - $id",
        );
        row_ok(
            sql => "SELECT * FROM amplicon_to_crRNA WHERE primer_pair_id = $count",
            tests => {
                '==' => {
                     crRNA_id  => 1,
                },
            },
            label => "primer pair to crRNA table - $id",
        );
        my $plate_id = $primer_type eq 'ext'   ?   1
            :           $primer_type eq 'int'   ?   2
            :                                       1
            ;
        foreach my $primer ( $mock_left_primer, $mock_right_primer ){
            row_ok(
               table => 'primer',
               where => [ primer_id => $primer->primer_id ],
               tests => {
                   'eq' => {
                        primer_sequence  => $primer->sequence,
                        primer_chr => $primer->seq_region,
                        primer_strand => $primer->seq_region_strand,
                        well_id => $well_id,
                   },
                   '==' => {
                        primer_start => $primer->seq_region_start,
                        primer_end => $primer->seq_region_end,
                        plate_id => $plate_id,
                   },
               },
               label => "primers stored - $id",
            );
        }
    
    }
    
    throws_ok{ $primer_pair_ad->store( undef ) }
        qr/primer_pair must be supplied in order to add oligos to the database/, 'calling store with undef primer pair';
    throws_ok{ $primer_pair_ad->store( 'primer' ) }
        qr/Supplied object must be a Crispr::PrimerPair object/, 'calling store with string';
    throws_ok{ $primer_pair_ad->store( $mock_p1 ) }
        qr/Supplied object must be a Crispr::PrimerPair object/, 'calling store with non PrimerPair object';
    throws_ok{ $primer_pair_ad->store( $mock_pp, ) }
        qr/At least one crRNA_id must be supplied in order to add oligos to the database/, 'calling store without any crRNA ids';
    throws_ok{ $primer_pair_ad->store( $mock_pp, 'primer' ) }
        qr/crRNA_ids must be supplied as an ArrayRef/, 'calling store with string as crRNA ids';
    throws_ok{ $primer_pair_ad->store( $mock_pp, [ $mock_pp ] ) }
        qr/Supplied object must be a Crispr::crRNA object/, 'calling store with crRNA ids in empty ArrayRef';
    
}

# drop databases
foreach ( @db_adaptors ){
    $_->destroy();
}

