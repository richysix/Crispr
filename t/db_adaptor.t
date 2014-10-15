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

use Crispr::DB::DBAdaptor;

Readonly my $TESTS_FOREACH_DBC => 1 + 17 + 5 + 2 + 38;    # Number of tests in the loop
plan tests => 2 * $TESTS_FOREACH_DBC;

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
my @db_adaptors;
foreach my $driver ( keys %db_connection_params ){
    push @db_adaptors, TestDB->new( $db_connection_params{$driver} );
}

SKIP: {
    skip 'No database connections available', $TESTS_FOREACH_DBC * 2 if !@db_adaptors;
    skip 'Only one database connection available', $TESTS_FOREACH_DBC
      if @db_adaptors == 1;
}

foreach my $db_adaptor ( @db_adaptors ){
    my $driver = $db_adaptor->driver;
    my $dbh = $db_adaptor->connection->dbh;
    # $dbh is a DBI database handle
    local $Test::DatabaseRow::dbh = $dbh;
    
    # get database connection using database adaptor
    $db_connection_params{ $driver }{ 'connection' } = $db_adaptor->connection;
    # make a new real DB Adaptor - tests calling with a hashref
    my $DB_ad = Crispr::DB::DBAdaptor->new( $db_connection_params{ $driver }, );
    # 1 test
    isa_ok( $DB_ad, 'Crispr::DB::DBAdaptor', "$driver: test inital Adaptor object class" );
    $tests++;
    
    # check method calls 17 tests
    my @methods = qw( driver host port dbname user
        pass dbfile connection db_params check_entry_exists_in_db
        fetch_rows_expecting_single_row fetch_rows_for_generic_select_statement _db_error_handling _data_source get_adaptor
        _target _cas9_prep 
    );
    
    foreach my $method ( @methods ) {
        ok( $DB_ad->can( $method ), "$driver: $method method test" );
        $tests++;
    }
    
    # test BUILDARGS method in constructor - 5 tests
    # create tmp config file
    open my $fh, '>', 'config.tmp';
    print $fh join("\n", map {
        if($_ ne 'connection' ){ join("\t", $_, $db_connection_params{$driver}{$_} ) }else{ () }
        } keys $db_connection_params{$driver} ), "\n";
    close($fh);
    ok( Crispr::DB::DBAdaptor->new( 'config.tmp' ), "$driver: config_file" );
    unlink( 'config.tmp' );
    throws_ok{ Crispr::DB::DBAdaptor->new( 'config2.tmp' ) }
        qr/Assumed\sthat.+is\sa\sconfig\sfile,\sbut\sfile\sdoes\snot\sexist./, "$driver: config file does not exist";
    throws_ok{ Crispr::DB::DBAdaptor->new( [] ) }
        qr/Could\snot\sparse\sarguments\sto\sBUILD\smethod/, "$driver: ArrayRef";
    ok( Crispr::DB::DBAdaptor->new(), "$driver: env variables" );
    ok( Crispr::DB::DBAdaptor->new( undef ), "$driver: env variables with undef parameter" );
    
    # check that BUILD method throws properly if driver is undefined or not mysql or sqlite- 2 tests
    $db_connection_params{ $driver }{ 'driver' } = undef;
    throws_ok{ Crispr::DB::DBAdaptor->new( $db_connection_params{ $driver }, ) }
        qr/Validation\sfailed/, "$driver: throws with undef driver";
    $db_connection_params{ $driver }{ 'driver' } = 'cheese';
    throws_ok{ Crispr::DB::DBAdaptor->new( $db_connection_params{ $driver }, ) }
        qr/Validation\sfailed/, "$driver: throws with incorrect driver";
    
    # check adaptor types - 38 tests
    isa_ok( $DB_ad->get_adaptor( 'target' ), 'Crispr::DB::TargetAdaptor', "$driver: get target adaptor" );
    isa_ok( $DB_ad->get_adaptor( 'targetadaptor' ), 'Crispr::DB::TargetAdaptor', "$driver: get targetadaptor adaptor" );
    isa_ok( $DB_ad->get_adaptor( 'target_adaptor' ), 'Crispr::DB::TargetAdaptor', "$driver: get target_adaptor adaptor" );
    
    isa_ok( $DB_ad->get_adaptor( 'cas9_prep' ), 'Crispr::DB::Cas9PrepAdaptor', "$driver: get cas9_prep adaptor" );
    isa_ok( $DB_ad->get_adaptor( 'cas9_prepadaptor' ), 'Crispr::DB::Cas9PrepAdaptor', "$driver: get cas9_prepadaptor adaptor" );
    isa_ok( $DB_ad->get_adaptor( 'cas9_prep_adaptor' ), 'Crispr::DB::Cas9PrepAdaptor', "$driver: get cas9_prep_adaptor adaptor" );

    SKIP: {
        skip "methods not implemented yet!", 31;
        
        isa_ok( $DB_ad->get_adaptor( 'crRNA' ), 'Crispr::DB::crRNAAdaptor', "$driver: get crRNA adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'crRNAadaptor' ), 'Crispr::DB::crRNAAdaptor', "$driver: get crRNAadaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'crRNA_adaptor' ), 'Crispr::DB::crRNAAdaptor', "$driver: get crRNA_adaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'crispr_pair' ), 'Crispr::DB::CrisprPairAdaptor', "$driver: get crispr_pair adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'crispr_pair_adaptor' ), 'Crispr::DB::CrisprPairAdaptor', "$driver: get crispr_pair_adaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'primer' ), 'Crispr::DB::PrimerAdaptor', "$driver: get primer adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'primeradaptor' ), 'Crispr::DB::PrimerAdaptor', "$driver: get primeradaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'primer_adaptor' ), 'Crispr::DB::PrimerAdaptor', "$driver: get primer_adaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'primer_pair' ), 'Crispr::DB::PrimerPairAdaptor', "$driver: get primer_pair adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'primer_pair_adaptor' ), 'Crispr::DB::PrimerPairAdaptor', "$driver: get primer_pair_adaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'plate' ), 'Crispr::DB::PlateAdaptor', "$driver: get plate adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'plateadaptor' ), 'Crispr::DB::PlateAdaptor', "$driver: get plateadaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'plate_adaptor' ), 'Crispr::DB::PlateAdaptor', "$driver: get plate_adaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'guiderna_prep' ), 'Crispr::DB::GuideRNAPrepAdaptor', "$driver: get guiderna_prep adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'guiderna_prepadaptor' ), 'Crispr::DB::GuideRNAPrepAdaptor', "$driver: get guiderna_prepadaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'guiderna_prep_adaptor' ), 'Crispr::DB::GuideRNAPrepAdaptor', "$driver: get guiderna_prep_adaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'injection_pool' ), 'Crispr::DB::InjectionPoolAdaptor', "$driver: get injection_pool adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'injection_pooladaptor' ), 'Crispr::DB::InjectionPoolAdaptor', "$driver: get injection_pooladaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'injection_pool_adaptor' ), 'Crispr::DB::InjectionPoolAdaptor', "$driver: get injection_pool_adaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'kasp' ), 'Crispr::DB::KaspAdaptor', "$driver: get kasp adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'kaspadaptor' ), 'Crispr::DB::KaspAdaptor', "$driver: get kaspadaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'kasp_adaptor' ), 'Crispr::DB::KaspAdaptor', "$driver: get kasp_adaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'plex' ), 'Crispr::DB::PlexAdaptor', "$driver: get plex adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'plexadaptor' ), 'Crispr::DB::PlexAdaptor', "$driver: get plexadaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'plex_adaptor' ), 'Crispr::DB::PlexAdaptor', "$driver: get plex_adaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'sample' ), 'Crispr::DB::SampleAdaptor', "$driver: get sample adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'sampleadaptor' ), 'Crispr::DB::SampleAdaptor', "$driver: get sampleadaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'sample_adaptor' ), 'Crispr::DB::SampleAdaptor', "$driver: get sample_adaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'subplex' ), 'Crispr::DB::SubplexAdaptor', "$driver: get subplex adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'subplexadaptor' ), 'Crispr::DB::SubplexAdaptor', "$driver: get subplexadaptor adaptor" );
        isa_ok( $DB_ad->get_adaptor( 'subplex_adaptor' ), 'Crispr::DB::SubplexAdaptor', "$driver: get subplex_adaptor adaptor" );
    }
    
    throws_ok { $DB_ad->get_adaptor( 'cheese' ) } qr/is\snot\sa\srecognised\sadaptor\stype/, "$driver: Throws on unrecognised adaptor type";
}

# drop databases
foreach ( @db_adaptors ){
    $_->destroy();
}

