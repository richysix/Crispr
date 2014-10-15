#!/usr/bin/env perl
# db_adaptor.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::DatabaseRow;
use Test::MockObject;
use Data::Dumper;
use autodie qw(:all);
use Getopt::Long;
use List::MoreUtils qw( any );
use DateTime;
use Readonly;

use Crispr::DB::DBConnection;

# Number of tests
Readonly my $TESTS_IN_COMMON => 1 + 11 + 1 + 5 + 2 + 6 + 6 + 6 + 60 + 1;
Readonly my %TESTS_FOREACH_DBC => (
    mysql => $TESTS_IN_COMMON + 5,
    sqlite => $TESTS_IN_COMMON + 2,
);
plan tests => $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite};

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

# reconnect to db using DBConnection
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
    
    # 1 test
    isa_ok( $db_connection, 'Crispr::DB::DBConnection', "$driver: test inital Adaptor object class" );
    $tests++;
    
    # check method calls 11 tests
    my @methods = qw( driver host port dbname user
        pass dbfile connection db_params _data_source
        get_adaptor
    );
    
    foreach my $method ( @methods ) {
        ok( $db_connection->can( $method ), "$driver: $method method test" );
        $tests++;
    }
    # 1 test
    is( $db_connection->driver, $driver, "$driver: check value of driver attribute" );
    if( $driver eq 'mysql' ){
        # 5 tests
        is( $db_connection->dbname, $db_connection_params{mysql}->{dbname}, "$driver: check value of dbname attribute" );
        is( $db_connection->host, $db_connection_params{mysql}->{host}, "$driver: check value of host attribute" );
        is( $db_connection->port, $db_connection_params{mysql}->{port}, "$driver: check value of port attribute" );
        is( $db_connection->user, $db_connection_params{mysql}->{user}, "$driver: check value of user attribute" );
        is( $db_connection->pass, $db_connection_params{mysql}->{pass}, "$driver: check value of pass attribute" );
    }
    else{
        # 2 tests
        is( $db_connection->dbname, $db_connection_params{sqlite}->{dbname}, "$driver: check value of dbname attribute" );
        is( $db_connection->dbfile, $db_connection_params{sqlite}->{dbfile}, "$driver: check value of dbfile attribute" );
    }
    
    # test BUILDARGS method in constructor - 5 tests
    # create tmp config file
    open my $fh, '>', 'config.tmp';
    print $fh join("\n", map {
        if($_ ne 'connection' ){ join("\t", $_, $db_connection_params{$driver}{$_} ) }else{ () }
        } keys $db_connection_params{$driver} ), "\n";
    close($fh);
    ok( Crispr::DB::DBConnection->new( 'config.tmp' ), "$driver: config_file" );
    unlink( 'config.tmp' );
    throws_ok{ Crispr::DB::DBConnection->new( 'config2.tmp' ) }
        qr/Assumed\sthat.+is\sa\sconfig\sfile,\sbut\sfile\sdoes\snot\sexist./, "$driver: config file does not exist";
    throws_ok{ Crispr::DB::DBConnection->new( [] ) }
        qr/Could\snot\sparse\sarguments\sto\sBUILD\smethod/, "$driver: ArrayRef";
    ok( Crispr::DB::DBConnection->new(), "$driver: env variables" );
    ok( Crispr::DB::DBConnection->new( undef ), "$driver: env variables with undef parameter" );
    
    # check that BUILD method throws properly if driver is undefined or not mysql or sqlite- 2 tests
    $db_connection_params{ $driver }{ 'driver' } = undef;
    throws_ok{ Crispr::DB::DBConnection->new( $db_connection_params{ $driver }, ) }
        qr/Validation\sfailed/, "$driver: throws with undef driver";
    $db_connection_params{ $driver }{ 'driver' } = 'cheese';
    throws_ok{ Crispr::DB::DBConnection->new( $db_connection_params{ $driver }, ) }
        qr/Validation\sfailed/, "$driver: throws with incorrect driver";
    
    # test get_adaptor: target - 6 tests
    my $target_adaptor = $db_connection->get_adaptor( 'target' );
    isa_ok( $target_adaptor, 'Crispr::DB::TargetAdaptor', "$driver: get target adaptor" );
    is( $target_adaptor->connection, $db_connection->connection, "$driver: check connections are the same" );
    $target_adaptor = $db_connection->get_adaptor( 'targetadaptor' );
    isa_ok( $target_adaptor, 'Crispr::DB::TargetAdaptor', "$driver: get target adaptor 2" );
    is( $target_adaptor->connection, $db_connection->connection, "$driver: check connections are the same 2" );
    $target_adaptor = $db_connection->get_adaptor( 'target_adaptor' );
    isa_ok( $target_adaptor, 'Crispr::DB::TargetAdaptor', "$driver: get target adaptor 3" );
    is( $target_adaptor->connection, $db_connection->connection, "$driver: check connections are the same 3" );
    
    # crRNA - 6 tests
    my $crRNA_adaptor = $db_connection->get_adaptor( 'crRNA' );
    isa_ok( $crRNA_adaptor, 'Crispr::DB::crRNAAdaptor', "$driver: get crRNA adaptor" );
    is( $crRNA_adaptor->connection, $db_connection->connection, "$driver: crRNA - check connections are the same" );
    $crRNA_adaptor = $db_connection->get_adaptor( 'crrna' );
    isa_ok( $crRNA_adaptor, 'Crispr::DB::crRNAAdaptor', "$driver: get crRNA adaptor 2" );
    is( $crRNA_adaptor->connection, $db_connection->connection, "$driver: crRNA - check connections are the same 2" );
    $crRNA_adaptor = $db_connection->get_adaptor( 'crRNA_adaptor' );
    isa_ok( $crRNA_adaptor, 'Crispr::DB::crRNAAdaptor', "$driver: get crRNA adaptor 3" );
    is( $crRNA_adaptor->connection, $db_connection->connection, "$driver: crRNA - check connections are the same 3" );

    # cas9_prep - 6 tests
    my $cas9_prep_adaptor = $db_connection->get_adaptor( 'cas9_prep' );
    isa_ok( $cas9_prep_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get cas9_prep adaptor" );
    is( $cas9_prep_adaptor->connection, $db_connection->connection, "$driver: cas9_prep - check connections are the same" );
    $cas9_prep_adaptor = $db_connection->get_adaptor( 'cas9prep' );
    isa_ok( $cas9_prep_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get cas9_prep adaptor 2" );
    is( $cas9_prep_adaptor->connection, $db_connection->connection, "$driver: cas9_prep - check connections are the same 2" );
    $cas9_prep_adaptor = $db_connection->get_adaptor( 'cas9_prep_adaptor' );
    isa_ok( $cas9_prep_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get cas9_prep adaptor 3" );
    is( $cas9_prep_adaptor->connection, $db_connection->connection, "$driver: cas9_prep - check connections are the same 3" );
    
    SKIP: {
        skip "methods not implemented yet!", 60;
        
        my $crispr_pair_adaptor = $db_connection->get_adaptor( 'crispr_pair' );
        isa_ok( $crispr_pair_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get crispr_pair adaptor" );
        is( $crispr_pair_adaptor->connection, $db_connection->connection, "$driver: crispr_pair - check connections are the same" );
        $crispr_pair_adaptor = $db_connection->get_adaptor( 'crisprpair' );
        isa_ok( $crispr_pair_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get crispr_pair adaptor 2" );
        is( $crispr_pair_adaptor->connection, $db_connection->connection, "$driver: crispr_pair - check connections are the same 2" );
        $crispr_pair_adaptor = $db_connection->get_adaptor( 'crispr_pair_adaptor' );
        isa_ok( $crispr_pair_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get crispr_pair adaptor 2" );
        is( $crispr_pair_adaptor->connection, $db_connection->connection, "$driver: crispr_pair - check connections are the same 2" );
        
        my $primer_adaptor = $db_connection->get_adaptor( 'primer' );
        isa_ok( $primer_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get primer adaptor" );
        is( $primer_adaptor->connection, $db_connection->connection, "$driver: primer - check connections are the same" );
        $primer_adaptor = $db_connection->get_adaptor( 'primeradaptor' );
        isa_ok( $primer_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get primer adaptor 2" );
        is( $primer_adaptor->connection, $db_connection->connection, "$driver: primer - check connections are the same 2" );
        $primer_adaptor = $db_connection->get_adaptor( 'primer_adaptor' );
        isa_ok( $primer_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get primer adaptor 3" );
        is( $primer_adaptor->connection, $db_connection->connection, "$driver: primer - check connections are the same 3" );
        
        my $primer_pair_adaptor = $db_connection->get_adaptor( 'primer_pair' );
        isa_ok( $primer_pair_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get primer_pair adaptor" );
        is( $primer_pair_adaptor->connection, $db_connection->connection, "$driver: primer_pair - check connections are the same" );
        $primer_pair_adaptor = $db_connection->get_adaptor( 'primer_pairadaptor' );
        isa_ok( $primer_pair_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get primer_pair adaptor 2" );
        is( $primer_pair_adaptor->connection, $db_connection->connection, "$driver: primer_pair - check connections are the same 2" );
        $primer_pair_adaptor = $db_connection->get_adaptor( 'primer_pair_adaptor' );
        isa_ok( $primer_pair_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get primer_pair adaptor 3" );
        is( $primer_pair_adaptor->connection, $db_connection->connection, "$driver: primer_pair - check connections are the same 3" );
        
        my $plate_adaptor = $db_connection->get_adaptor( 'plate' );
        isa_ok( $plate_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get plate adaptor" );
        is( $plate_adaptor->connection, $db_connection->connection, "$driver: plate - check connections are the same" );
        $plate_adaptor = $db_connection->get_adaptor( 'plateadaptor' );
        isa_ok( $plate_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get plate adaptor 2" );
        is( $plate_adaptor->connection, $db_connection->connection, "$driver: plate - check connections are the same 2" );
        $plate_adaptor = $db_connection->get_adaptor( 'plate_adaptor' );
        isa_ok( $plate_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get plate adaptor 3" );
        is( $plate_adaptor->connection, $db_connection->connection, "$driver: plate - check connections are the same 3" );
        
        my $guideRNA_prep_adaptor = $db_connection->get_adaptor( 'guideRNA_prep' );
        isa_ok( $guideRNA_prep_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get guideRNA_prep adaptor" );
        is( $guideRNA_prep_adaptor->connection, $db_connection->connection, "$driver: guideRNA_prep - check connections are the same" );
        $guideRNA_prep_adaptor = $db_connection->get_adaptor( 'guideRNA_prepadaptor' );
        isa_ok( $guideRNA_prep_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get guideRNA_prep adaptor 2" );
        is( $guideRNA_prep_adaptor->connection, $db_connection->connection, "$driver: guideRNA_prep - check connections are the same 2" );
        $guideRNA_prep_adaptor = $db_connection->get_adaptor( 'guideRNA_prep_adaptor' );
        isa_ok( $guideRNA_prep_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get guideRNA_prep adaptor 3" );
        is( $guideRNA_prep_adaptor->connection, $db_connection->connection, "$driver: guideRNA_prep - check connections are the same 3" );
        
        my $injection_pool_adaptor = $db_connection->get_adaptor( 'injection_pool' );
        isa_ok( $injection_pool_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get injection_pool adaptor" );
        is( $injection_pool_adaptor->connection, $db_connection->connection, "$driver: injection_pool - check connections are the same" );
        $injection_pool_adaptor = $db_connection->get_adaptor( 'injection_pooladaptor' );
        isa_ok( $injection_pool_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get injection_pool adaptor 2" );
        is( $injection_pool_adaptor->connection, $db_connection->connection, "$driver: injection_pool - check connections are the same 2" );
        $injection_pool_adaptor = $db_connection->get_adaptor( 'injection_pool_adaptor' );
        isa_ok( $injection_pool_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get injection_pool adaptor 3" );
        is( $injection_pool_adaptor->connection, $db_connection->connection, "$driver: injection_pool - check connections are the same 3" );
        
        my $kasp_adaptor = $db_connection->get_adaptor( 'kasp' );
        isa_ok( $kasp_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get kasp adaptor" );
        is( $kasp_adaptor->connection, $db_connection->connection, "$driver: kasp - check connections are the same" );
        $kasp_adaptor = $db_connection->get_adaptor( 'kaspadaptor' );
        isa_ok( $kasp_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get kasp adaptor 2" );
        is( $kasp_adaptor->connection, $db_connection->connection, "$driver: kasp - check connections are the same 2" );
        $kasp_adaptor = $db_connection->get_adaptor( 'kasp_adaptor' );
        isa_ok( $kasp_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get kasp adaptor 3" );
        is( $kasp_adaptor->connection, $db_connection->connection, "$driver: kasp - check connections are the same 3" );
        
        my $plex_adaptor = $db_connection->get_adaptor( 'plex' );
        isa_ok( $plex_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get plex adaptor" );
        is( $plex_adaptor->connection, $db_connection->connection, "$driver: plex - check connections are the same" );
        $plex_adaptor = $db_connection->get_adaptor( 'plexadaptor' );
        isa_ok( $plex_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get plex adaptor 2" );
        is( $plex_adaptor->connection, $db_connection->connection, "$driver: plex - check connections are the same 2" );
        $plex_adaptor = $db_connection->get_adaptor( 'plex_adaptor' );
        isa_ok( $plex_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get plex adaptor 3" );
        is( $plex_adaptor->connection, $db_connection->connection, "$driver: plex - check connections are the same 3" );
        
        my $subplex_adaptor = $db_connection->get_adaptor( 'subplex' );
        isa_ok( $subplex_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get subplex adaptor" );
        is( $subplex_adaptor->connection, $db_connection->connection, "$driver: subplex - check connections are the same" );
        $subplex_adaptor = $db_connection->get_adaptor( 'subplexadaptor' );
        isa_ok( $subplex_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get subplex adaptor 2" );
        is( $subplex_adaptor->connection, $db_connection->connection, "$driver: subplex - check connections are the same 2" );
        $subplex_adaptor = $db_connection->get_adaptor( 'subplex_adaptor' );
        isa_ok( $subplex_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get subplex adaptor 3" );
        is( $subplex_adaptor->connection, $db_connection->connection, "$driver: subplex - check connections are the same 3" );
        
        my $sample_adaptor = $db_connection->get_adaptor( 'sample' );
        isa_ok( $sample_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get sample adaptor" );
        is( $sample_adaptor->connection, $db_connection->connection, "$driver: sample - check connections are the same" );
        $sample_adaptor = $db_connection->get_adaptor( 'sampleadaptor' );
        isa_ok( $sample_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get sample adaptor 2" );
        is( $sample_adaptor->connection, $db_connection->connection, "$driver: sample - check connections are the same 2" );
        $sample_adaptor = $db_connection->get_adaptor( 'sample_adaptor' );
        isa_ok( $sample_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get sample adaptor 3" );
        is( $sample_adaptor->connection, $db_connection->connection, "$driver: sample - check connections are the same 3" );
    }
    
    throws_ok { $db_connection->get_adaptor( 'cheese' ) } qr/is\snot\sa\srecognised\sadaptor\stype/, "$driver: Throws on unrecognised adaptor type";
    
    # drop database
    $test_db_connections{$driver}->destroy();
}
