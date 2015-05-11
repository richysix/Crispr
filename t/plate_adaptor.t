#!/usr/bin/env perl
# target_adaptor.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::DatabaseRow;
use Test::MockObject;
use Data::Dumper;
use Readonly;

use Crispr::DB::PlateAdaptor;
use Crispr::DB::PrimerPairAdaptor;

Readonly my $TESTS_IN_COMMON => 1 + 15 + 4 + 3 + 1 + 6 + 6 + 6 + 3 + 3;
Readonly my %TESTS_FOREACH_DBC => (
    mysql => $TESTS_IN_COMMON,
    sqlite => $TESTS_IN_COMMON,
);
plan tests => $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite};

use DateTime;
#get current date
my $date_obj = DateTime->now();
my $todays_date = $date_obj->ymd;

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
# TestDB creates test database, connects to it and gets db handle
my @db_connections;
foreach my $driver ( keys %db_connection_params ){
    push @db_connections, TestDB->new( $db_connection_params{$driver} );
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
    
    # make a mock DBConnection object
    my $mock_db_connection = Test::MockObject->new();
    $mock_db_connection->set_isa( 'Crispr::DB::DBConnection' );
    $mock_db_connection->mock( 'dbname', sub { return $db_connection->dbname } );
    $mock_db_connection->mock( 'connection', sub { return $db_connection->connection } );
    
    # make a PrimerPair adaptor
    my $primer_pair_ad = Crispr::DB::PrimerPairAdaptor->new(
        db_connection => $mock_db_connection,
    );
    
    # make a new real Plate Adaptor
    my $plate_ad = Crispr::DB::PlateAdaptor->new(
        db_connection => $mock_db_connection,
        primer_pair_adaptor => $primer_pair_ad,
    );
    # 1 test
    isa_ok( $plate_ad, 'Crispr::DB::PlateAdaptor' );
    
    # check methods 15 tests
    my @methods = qw( dbname db_connection connection check_entry_exists_in_db fetch_rows_expecting_single_row
        fetch_rows_for_generic_select_statement _db_error_handling store get_plate_id_from_name fetch_empty_plate_by_id
        fetch_empty_plate_by_name _fetch_empty_plate_by_attribute fetch_crispr_plate_by_plate_name _make_new_plate_from_db _build_crRNA_adaptor
    );
    
    foreach my $method ( @methods ) {
        can_ok( $plate_ad, $method );
    }
    
    # Should have used a mock object for this really, change sometime
    use Crispr::Plate;
    
    # make a new fully specified plate
    my $plate_1 = Crispr::Plate->new(
        id => '1',
        plate_name => 'CR-000001a',
        plate_type => '96',
        plate_category => 'cloning_oligos',
        ordered => $date_obj,
        received => $date_obj,
    );
    
    # make a new plate with only name specified
    my $plate_2 = Crispr::Plate->new(
        plate_name => 'CR-000001b',
        plate_category => 'pcr_primers',
    );
    
    my $plate_3 = Crispr::Plate->new(
        plate_name => 'CR-000002a',
        plate_type => '384',
        plate_category => 'expression_construct',
    );
    
    # store target
    $plate_1 = $plate_ad->store($plate_1);
    $plate_2 = $plate_ad->store($plate_2);
    $plate_3 = $plate_ad->store($plate_3);
    
    # check plate id - 4 tests
    is( $plate_1->plate_id, 1, 'Check primary key' );
    is( $plate_2->plate_id, 2, 'Check primary key' );
    is( $plate_3->plate_id, 3, 'Check primary key' );
    throws_ok { $plate_ad->store($plate_3) } qr/PLATE\sALREADY\sEXISTS/, 'Check throws correctly if plate already exists in db.';
    
    # check database row
    # 3 tests
    row_ok(
       table => 'plate',
       where => [ plate_id => 1 ],
       tests => {
           'eq' => {
                plate_name => 'CR-000001a',
                plate_type => '96',
                ordered  => $todays_date,
                received => $todays_date,
                plate_category => 'cloning_oligos',
           },
       },
       label => 'Plate 1 stored',
    );
    
    row_ok(
       table => 'plate',
       where => [ plate_id => 2 ],
       tests => {
           'eq' => {
                plate_name => 'CR-000001b',
                plate_type => '96',
                ordered  => undef,
                received => undef,
                plate_category => 'pcr_primers',
           },
       },
       label => 'Plate 2 stored',
    );
    
    row_ok(
       table => 'plate',
       where => [ plate_id => 3 ],
       tests => {
           'eq' => {
                plate_name => 'CR-000002a',
                plate_type => '384',
                ordered  => undef,
                received => undef,
                plate_category => 'expression_construct',
           },
       },
       label => 'Plate 3 stored',
    );
    
    my $plate_4 = Crispr::Plate->new(
    );
    
    throws_ok { $plate_ad->store($plate_4) } qr/Plate\smust\shave\sa\splate_name/, 'No plate name';
    
    # fetch empty plates by id from database
    my $plate_5 = $plate_ad->fetch_empty_plate_by_id( 1 );
    # 6 tests
    is( $plate_5->plate_id, 1, 'Get id 1' );
    is( $plate_5->plate_name, 'CR-000001a', 'Get plate name 1' );
    is( $plate_5->plate_type, '96', 'Get plate type 1' );
    is( $plate_5->plate_category, 'cloning_oligos', 'Get plate category 1' );
    is( $plate_5->ordered, $todays_date, 'Get ordered 1' );
    is( $plate_5->received, $todays_date, 'Get received 1' );
    
    my $plate_6 = $plate_ad->fetch_empty_plate_by_id( 3 );
    # 6 tests
    is( $plate_6->plate_id, 3, 'Get id 2' );
    is( $plate_6->plate_name, 'CR-000002a', 'Get plate name 2' );
    is( $plate_6->plate_type, '384', 'Get plate type 2' );
    is( $plate_6->plate_category, 'expression_construct', 'Get plate category 2' );
    is( $plate_6->ordered, undef, 'Get ordered 2' );
    is( $plate_6->received, undef, 'Get received 2' );
    
    # fetch empty plate by name from database
    my $plate_7 = $plate_ad->fetch_empty_plate_by_name( 'CR-000001a' );
    # 6 tests
    is( $plate_7->plate_id, 1, 'Get id 3' );
    is( $plate_7->plate_name, 'CR-000001a', 'Get plate name 3' );
    is( $plate_7->plate_type, '96', 'Get plate type 3' );
    is( $plate_7->plate_category, 'cloning_oligos', 'Get plate type 3' );
    is( $plate_7->ordered, $todays_date, 'Get ordered 3' );
    is( $plate_7->received, $todays_date, 'Get received 3' );
    
    # check getting id using plate_name - 3 tests
    is( $plate_ad->get_plate_id_from_name( 'CR-000001a' ), 1, 'fetch id from plate_name - 1');
    is( $plate_ad->get_plate_id_from_name( 'CR-000001b' ), 2, 'fetch id from plate_name - 2');
    is( $plate_ad->get_plate_id_from_name( 'CR-000002a' ), 3, 'fetch id from plate_name - 3');
    
    # test method fetch_primer_pair_plate_by_plate_name
    # add plate and primers directly to db
    #my $mock_plate = Test::MockObject->new();
    #$mock_plate->mock('plate_id', sub { return 4 } );
    #$mock_plate->mock('plate_name', sub { return 'CR_000001f' } );
    #$mock_plate->mock('plate_type', sub { return 96 } );
    #$mock_plate->mock('plate_category', sub { return 'pcr_primers'} );
    #$mock_plate->mock('ordered', sub { return undef } );
    #$mock_plate->mock('received', sub { return undef } );
    #
    #my $statement = "insert into plate values( ?, ?, ?, ?, ?, ? );";
    #$sth = $dbh->prepare($statement);
    #$sth->execute( $mock_plate->plate_id, $mock_plate->plate_name,
    #    $mock_plate->plate_type, $mock_plate->plate_category,
    #    $mock_plate->ordered, $mock_plate->received,
    #);
    
    my $mock_l_primer = Test::MockObject->new();
    $mock_l_primer->mock('primer_id', sub { return 1 } );
    $mock_l_primer->mock('seq_region', sub { return '5'} );
    $mock_l_primer->mock('seq_region_start', sub { return 2403050 } );
    $mock_l_primer->mock('seq_region_end', sub { return 2403073 } );
    $mock_l_primer->mock('seq_region_strand', sub { return '1' } );
    $mock_l_primer->mock('sequence', sub { return 'ACGATGACAGATAGACAGAAGTCG' } );
    $mock_l_primer->mock('primer_tail', sub { return undef } );
    $mock_l_primer->set_isa('Crispr::Primer');
    
    my $mock_r_primer = Test::MockObject->new();
    $mock_r_primer->mock('primer_id', sub { return 2 } );
    $mock_r_primer->mock('seq_region', sub { return '5'} );
    $mock_r_primer->mock('seq_region_start', sub { return 2403250 } );
    $mock_r_primer->mock('seq_region_end', sub { return 2403273 } );
    $mock_r_primer->mock('seq_region_strand', sub { return '-1' } );
    $mock_r_primer->mock('sequence', sub { return 'AGATAGACTAGACATTCAGATCAG' } );
    $mock_r_primer->mock('primer_tail', sub { return undef } );
    $mock_r_primer->set_isa('Crispr::Primer');
    
    my $primer_statement = 'insert into primer values( ?, ?, ?, ?, ?, ?, ?, ?, ? );';
    $sth = $dbh->prepare($primer_statement);
    foreach my $primer ( $mock_l_primer, $mock_r_primer ){
        $sth->execute(
            $primer->primer_id, $primer->sequence,
            $primer->seq_region,
            $primer->seq_region_start, $primer->seq_region_end,
            $primer->seq_region_strand,
            $primer_tail,
            2, 'A01',
        );
    }
    my $mock_primer_pair = Test::MockObject->new();
    $mock_primer_pair->mock('primer_pair_id', sub { return 1 } );
    $mock_primer_pair->mock('type', sub { return 'ext-illumina' } );
    $mock_primer_pair->mock('product_size', sub { return 224 } );

    my $pair_statement = "insert into primer_pair values( ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    
    $sth = $dbh->prepare($pair_statement);
    $sth->execute(
        $mock_primer_pair->primer_pair_id,
        $mock_primer_pair->type,
        $mock_l_primer->primer_id,
        $mock_r_primer->primer_id,
        $mock_l_primer->seq_region,
        $mock_l_primer->seq_region_start,
        $mock_r_primer->seq_region_end,
        $mock_l_primer->seq_region_strand,
        $mock_primer_pair->product_size,
    );
    
    # 3 tests
    my $pp_plate;
    throws_ok { $plate_ad->fetch_primer_pair_plate_by_plate_name( 'CR_000001b' ) }
        qr/Plate CR_000001b does not exist in the database/, 'fetch primer plate throws if plate nonexistant or empty';
    ok( $pp_plate = $plate_ad->fetch_primer_pair_plate_by_plate_name( 'CR-000001b' ), 'fetch primer plate' );
    
    my $well = $pp_plate->return_well( 'A01');
    my $pp_name = $mock_l_primer->seq_region . ':' .
        $mock_l_primer->seq_region_start . '-' .
        $mock_r_primer->seq_region_end . ':' .
        $mock_l_primer->seq_region_strand;
    my $pp_summary = join(q{,}, $pp_name, $mock_primer_pair->product_size,
        $mock_l_primer->seq_region . ':' .
        $mock_l_primer->seq_region_start . '-' .
        $mock_l_primer->seq_region_end . ':' .
        $mock_l_primer->seq_region_strand,
        $mock_l_primer->sequence,
        $mock_r_primer->seq_region . ':' .
        $mock_r_primer->seq_region_start . '-' .
        $mock_r_primer->seq_region_end . ':' .
        $mock_r_primer->seq_region_strand,
        $mock_r_primer->sequence,
    );
    is( join(",", $well->contents->primer_pair_summary, ), $pp_summary,'check primer_pair info from db');
}

# drop databases
foreach ( @db_adaptors ){
    $_->destroy();
}
