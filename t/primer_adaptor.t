#!/usr/bin/env perl
# primer_adaptor.t
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

Readonly my $TESTS_FOREACH_DBC => 1 + 14 + $count_output * 2 + 2 + 9;
plan tests => 2 * $TESTS_FOREACH_DBC;

use Crispr::DB::DBConnection;
use Crispr::DB::PrimerAdaptor;

##  database tests  ##
# Module with a function for creating an empty test database
# and returning a database connection
use lib 't/lib';
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
my @db_connections;
foreach my $driver ( keys %db_connection_params ){
    push @db_connections, TestDB->new( $db_connection_params{$driver} );
}

SKIP: {
    skip 'No database connections available', $TESTS_FOREACH_DBC * 2 if !@db_connections;
    skip 'Only one database connection available', $TESTS_FOREACH_DBC
      if @db_connections == 1;
}

foreach my $db_connection ( @db_connections ){
    my $driver = $db_connection->driver;
    my $dbh = $db_connection->connection->dbh;

    # $dbh is a DBI database handle
    local $Test::DatabaseRow::dbh = $dbh;
    
    # make a mock DBConnection object
    my $mock_db_connection = Test::MockObject->new();
    $mock_db_connection->set_isa( 'Crispr::DB::DBConnection' );
    $mock_db_connection->mock( 'dbname', sub { return $db_connection->dbname } );
    $mock_db_connection->mock( 'connection', sub { return $db_connection->connection } );
    
    # get adaptors
    my $plate_ad = Crispr::DB::PlateAdaptor->new( db_connection => $mock_db_connection, );
    my $primer_ad = Crispr::DB::PrimerAdaptor->new( db_connection => $mock_db_connection, );
    # 1 test
    isa_ok( $primer_ad, 'Crispr::DB::PrimerAdaptor' );
    
    # check attributes and methods exist 3 + 11 tests
    my @attributes = ( qw{ dbname db_connection connection } );
    
    my @methods = (
        qw{ store _split_primer_into_seq_and_tail fetch_by_id fetch_by_name _fetch_primers_by_attributes
        _make_new_primer_from_db _build_plate_adaptor check_entry_exists_in_db fetch_rows_expecting_single_row fetch_rows_for_generic_select_statement
            _db_error_handling }
    );

    foreach my $attribute ( @attributes ) {
        can_ok( $primer_ad, $attribute );
    }
    foreach my $method ( @methods ) {
        can_ok( $primer_ad, $method );
    }
    
    my $count = 0;
    # load data into objects
    open my $fh, '<', $test_data or die "Couldn't open file: $test_data!\n";
    my ( $l_p_id, $r_p_id, $pair_id ) = ( -1, 0, 0 );
    while(<$fh>){
        $count++;
        chomp;
        my ( $id, $primer_type, $plate_num, $well_id, $primer_pair_id,
            $left_primer_name, $left_primer_seq, $right_primer_name, $right_primer_seq, $product_size, ) = split /\s/, $_;
        
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
        my ( $l_chr, $l_region, $l_strand ) = split /:/, $left_primer_name;
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
        
        my ( $r_chr, $r_region, $r_strand ) = split /:/, $right_primer_name;
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
        
        # store left and right primer
        $mock_well->mock('contents', sub { return $mock_left_primer } );
        $primer_ad->store( $mock_well );
        $mock_well->mock('contents', sub { return $mock_right_primer } );
        $primer_ad->store( $mock_well );
        
        # check database rows - 2 tests
        foreach my $primer ( $mock_left_primer, $mock_right_primer ){
            row_ok(
               table => 'primer',
               where => [ primer_id => $primer->primer_id ],
               tests => {
                   'eq' => {
                        primer_sequence  => $primer->sequence,
                        primer_tail => undef,
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
               label => "$driver: primers stored - $id",
            );
        }
        
    }
    
    my $mock_left_primer = Test::MockObject->new();
    $l_p_id += 2;
    $mock_left_primer->mock( 'sequence', sub { return 'ACACTCTTTCCCTACACGACGCTCTTCCGATCTTGGGAGTCCTGCTAATCTCTC' } );
    $mock_left_primer->mock( 'seq_region', sub { return 4 } );
    $mock_left_primer->mock( 'seq_region_start', sub { return 60341090 } );
    $mock_left_primer->mock( 'seq_region_end', sub { return 60341110 } );
    $mock_left_primer->mock( 'seq_region_strand', sub { return '1' } );
    $mock_left_primer->mock( 'well_id', sub { return undef } );
    $mock_left_primer->mock( 'primer_name', sub { return '4:60341090-60341110:1' } );
    $mock_left_primer->set_isa('Crispr::Primer');
    $mock_left_primer->mock('primer_id', sub { my @args = @_; if( $_[1]){ return $_[1] }else{ return $l_p_id} } );
    
    my $mock_right_primer = Test::MockObject->new();
    $r_p_id += 2;
    $mock_right_primer->mock( 'sequence', sub { return 'TCGGCATTCCTGCTGAACCGCTCTTCCGATCTCACAGCACTGTATATAAACAGTG' } );
    $mock_right_primer->mock( 'seq_region', sub { return 4 } );
    $mock_right_primer->mock( 'seq_region_start', sub { return 60341311 } );
    $mock_right_primer->mock( 'seq_region_end', sub { return 60341333 } );
    $mock_right_primer->mock( 'seq_region_strand', sub { return '-1' } );
    $mock_right_primer->mock( 'primer_name', sub { return '4:60341311-60341333:-1' } );
    $mock_right_primer->mock( 'well_id', sub { return undef } );
    $mock_right_primer->set_isa('Crispr::Primer');
    $mock_right_primer->mock('primer_id', sub { my @args = @_; if( $_[1]){ return $_[1] }else{ return $r_p_id} } );
    
    # store primers
    $primer_ad->store( $mock_left_primer );
    $primer_ad->store( $mock_right_primer );
    
    # check database rows - 2 tests
    foreach my $primer ( $mock_left_primer, $mock_right_primer ){
        my $primer_seq = $primer->sequence;
        my $primer_tail;
        if( $primer_seq =~ m/\A ACACTCTTTCCCTACACGACGCTCTTCCGATCT/xms ){
            $primer_seq =~ s/\A ACACTCTTTCCCTACACGACGCTCTTCCGATCT//xms;
            $primer_tail = 'ACACTCTTTCCCTACACGACGCTCTTCCGATCT';
        }
        elsif( $primer_seq =~ m/\A TCGGCATTCCTGCTGAACCGCTCTTCCGATCT/xms){
            $primer_seq =~ s/\A TCGGCATTCCTGCTGAACCGCTCTTCCGATCT//xms;
            $primer_tail = 'TCGGCATTCCTGCTGAACCGCTCTTCCGATCT';
        }
        row_ok(
           table => 'primer',
           where => [ primer_id => $primer->primer_id ],
           tests => {
               'eq' => {
                    primer_sequence  => $primer_seq,
                    primer_tail => $primer_tail,
                    primer_chr => $primer->seq_region,
                    primer_strand => $primer->seq_region_strand,
                    well_id => undef,
               },
               '==' => {
                    primer_start => $primer->seq_region_start,
                    primer_end => $primer->seq_region_end,
                    plate_id => undef,
               },
           },
           label => "$driver: primers stored - with tail",
        );
    }
    
    # test fetch methods
    # _fetch - 9 tests
    my $primer;
    ok( $primers = $primer_ad->_fetch( 'primer_id = ?',
        [ $mock_left_primer->primer_id, ] ), "$driver: Test _fetch method" );
    check_attributes( $primers->[0], $mock_left_primer, $driver, '_fetch' );
    
    $db_connection->destroy();
}

# 8 tests per call
sub check_attributes {
    my ( $obj_1, $obj_2, $driver, $method, ) = @_;
    is( $obj_1->sequence, $obj_2->sequence, "$driver: object from db $method - check primer seq" );
    is( $obj_1->primer_id, $obj_2->primer_id, "$driver: object from db $method - check primer id" );
    is( $obj_1->seq_region, $obj_2->seq_region, "$driver: object from db $method - check primer chr" );
    is( $obj_1->seq_region_start, $obj_2->seq_region_start, "$driver: object from db $method - check primer start" );
    is( $obj_1->seq_region_end, $obj_2->seq_region_end, "$driver: object from db $method - check primer end" );
    is( $obj_1->seq_region_strand, $obj_2->seq_region_strand, "$driver: object from db $method - check primer strand" );
    is( $obj_1->primer_name, $obj_2->primer_name, "$driver: object from db $method - check primer primer_name" );
    is( $obj_1->well_id, $obj_2->well_id, "$driver: object from db $method - check primer well id" );
}

