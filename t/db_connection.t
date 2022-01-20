#!/usr/bin/env perl
# db_adaptor.t
use warnings;
use strict;

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
use English qw( -no_match_vars );

use Crispr::DB::DBConnection;

# Number of tests
Readonly my $TESTS_IN_COMMON => 1 + 11 + 1 + 3 + 2 + ( 6 * 14 ) + 1;
Readonly my %TESTS_FOREACH_DBC => (
    mysql => $TESTS_IN_COMMON + 7,
    sqlite => $TESTS_IN_COMMON + 4,
);
if( $ENV{NO_DB} ) {
    plan skip_all => 'Not testing database';
}
else {
    plan tests => $TESTS_FOREACH_DBC{mysql} + $TESTS_FOREACH_DBC{sqlite};
}

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

foreach my $db_connection ( @{$db_connections} ){
    my $driver = $db_connection->driver;
    my $dbh = $db_connection->connection->dbh;
    # $dbh is a DBI database handle
    local $Test::DatabaseRow::dbh = $dbh;
    
    if($driver eq 'mysql' ){
        $ENV{MYSQL_DBNAME} = $ENV{MYSQL_TEST_DBNAME};
    }
    elsif( $driver eq 'sqlite' ){
        foreach my $variable ( qw{MYSQL_TEST_DBNAME MYSQL_DBHOST MYSQL_DBPORT MYSQL_DBUSER MYSQL_DBPASS } ){
            $ENV{$variable} = undef;
        }
    }
    # make a real DBConnection object
    my $db_conn = Crispr::DB::DBConnection->new( $db_connection_params->{$driver} );
    
    # 1 test
    isa_ok( $db_conn, 'Crispr::DB::DBConnection', "$driver: test inital Adaptor object class" );
    
    # check method calls 11 tests
    my @methods = qw( driver host port dbname user
        pass dbfile connection db_params _data_source
        get_adaptor
    );
    
    foreach my $method ( @methods ) {
        ok( $db_conn->can( $method ), "$driver: $method method test" );
    }
    # 1 test
    is( $db_conn->driver, $driver, "$driver: check value of driver attribute" );
    if( $driver eq 'mysql' ){
        # 7 tests
        is( $db_conn->dbname, $db_connection_params->{mysql}->{dbname}, "$driver: check value of dbname attribute" );
        is( $db_conn->host, $db_connection_params->{mysql}->{host}, "$driver: check value of host attribute" );
        is( $db_conn->port, $db_connection_params->{mysql}->{port}, "$driver: check value of port attribute" );
        is( $db_conn->user, $db_connection_params->{mysql}->{user}, "$driver: check value of user attribute" );
        is( $db_conn->pass, $db_connection_params->{mysql}->{pass}, "$driver: check value of pass attribute" );
        warning_like { Crispr::DB::DBConnection->new() }
            qr/No config file or options supplied/,
            "$driver: env variables";
        warning_like { Crispr::DB::DBConnection->new( undef ) }
            qr/No config file or options supplied/,
            "$driver: env variables with undef parameter";
    }
    else{
        # 4 tests
        is( $db_conn->dbname, $db_connection_params->{sqlite}->{dbname}, "$driver: check value of dbname attribute" );
        is( $db_conn->dbfile, $db_connection_params->{sqlite}->{dbfile}, "$driver: check value of dbfile attribute" );
        
        throws_ok {
                warnings_like { Crispr::DB::DBConnection->new() }
                    [ qr/No config file or options supplied/,
                        qr/MySQL environment variables are not set/,
                    ]
            }
            qr/These environment variables need to be set/,
            "$driver: throws if no env variables set";
        
        $ENV{SQLITE_DBNAME} = 'test';
        $ENV{SQLITE_DBFILE} = 'test.db';
        warnings_like { Crispr::DB::DBConnection->new() }
            [ qr/No config file or options supplied/,
                qr/MySQL environment variables are not set/,
            ],
            "$driver: env variables";
    }
    
    # test BUILDARGS method in constructor - 3 tests
    # create tmp config file
    open my $fh, '>', 'config.tmp';
    print $fh join("\n", map {
        if($_ ne 'connection' ){ join("\t", $_, $db_connection_params->{$driver}{$_} ) }else{ () }
        } keys %{ $db_connection_params->{$driver} } ), "\n";
    close($fh);
    ok( Crispr::DB::DBConnection->new( 'config.tmp' ), "$driver: config_file" );
    unlink( 'config.tmp' );
    throws_ok { Crispr::DB::DBConnection->new( 'config2.tmp' ) }
        qr/Assumed\sthat.+is\sa\sconfig\sfile,\sbut\sfile\sdoes\snot\sexist./, "$driver: config file does not exist";
    throws_ok { Crispr::DB::DBConnection->new( [] ) }
        qr/Could\snot\sparse\sarguments\sto\sBUILD\smethod/, "$driver: ArrayRef";
    
    # check that BUILD method throws properly if driver is undefined or not mysql or sqlite- 2 tests
    $db_connection_params->{ $driver }{ 'driver' } = undef;
    throws_ok { Crispr::DB::DBConnection->new( $db_connection_params->{ $driver }, ) }
        qr/Validation\sfailed/, "$driver: throws with undef driver";
    $db_connection_params->{ $driver }{ 'driver' } = 'cheese';
    throws_ok { Crispr::DB::DBConnection->new( $db_connection_params->{ $driver }, ) }
        qr/Validation\sfailed/, "$driver: throws with incorrect driver";
    
    # test get_adaptor: target - 6 tests
    my $target_adaptor = $db_conn->get_adaptor( 'target' );
    isa_ok( $target_adaptor, 'Crispr::DB::TargetAdaptor', "$driver: get target adaptor" );
    is( $target_adaptor->connection, $db_conn->connection, "$driver: check connections are the same" );
    $target_adaptor = $db_conn->get_adaptor( 'targetadaptor' );
    isa_ok( $target_adaptor, 'Crispr::DB::TargetAdaptor', "$driver: get target adaptor 2" );
    is( $target_adaptor->connection, $db_conn->connection, "$driver: check connections are the same 2" );
    $target_adaptor = $db_conn->get_adaptor( 'target_adaptor' );
    isa_ok( $target_adaptor, 'Crispr::DB::TargetAdaptor', "$driver: get target adaptor 3" );
    is( $target_adaptor->connection, $db_conn->connection, "$driver: check connections are the same 3" );
    
    # crRNA - 6 tests
    my $crRNA_adaptor = $db_conn->get_adaptor( 'crRNA' );
    isa_ok( $crRNA_adaptor, 'Crispr::DB::crRNAAdaptor', "$driver: get crRNA adaptor" );
    is( $crRNA_adaptor->connection, $db_conn->connection, "$driver: crRNA - check connections are the same" );
    $crRNA_adaptor = $db_conn->get_adaptor( 'crrna' );
    isa_ok( $crRNA_adaptor, 'Crispr::DB::crRNAAdaptor', "$driver: get crRNA adaptor 2" );
    is( $crRNA_adaptor->connection, $db_conn->connection, "$driver: crRNA - check connections are the same 2" );
    $crRNA_adaptor = $db_conn->get_adaptor( 'crRNA_adaptor' );
    isa_ok( $crRNA_adaptor, 'Crispr::DB::crRNAAdaptor', "$driver: get crRNA adaptor 3" );
    is( $crRNA_adaptor->connection, $db_conn->connection, "$driver: crRNA - check connections are the same 3" );

    # cas9_prep - 6 tests
    my $cas9_prep_adaptor = $db_conn->get_adaptor( 'cas9_prep' );
    isa_ok( $cas9_prep_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get cas9_prep adaptor" );
    is( $cas9_prep_adaptor->connection, $db_conn->connection, "$driver: cas9_prep - check connections are the same" );
    $cas9_prep_adaptor = $db_conn->get_adaptor( 'cas9prep' );
    isa_ok( $cas9_prep_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get cas9_prep adaptor 2" );
    is( $cas9_prep_adaptor->connection, $db_conn->connection, "$driver: cas9_prep - check connections are the same 2" );
    $cas9_prep_adaptor = $db_conn->get_adaptor( 'cas9_prep_adaptor' );
    isa_ok( $cas9_prep_adaptor, 'Crispr::DB::Cas9PrepAdaptor', "$driver: get cas9_prep adaptor 3" );
    is( $cas9_prep_adaptor->connection, $db_conn->connection, "$driver: cas9_prep - check connections are the same 3" );
    
    # crispr pair
    my $crispr_pair_adaptor = $db_conn->get_adaptor( 'crispr_pair' );
    isa_ok( $crispr_pair_adaptor, 'Crispr::DB::CrisprPairAdaptor', "$driver: get crispr_pair adaptor" );
    is( $crispr_pair_adaptor->connection, $db_conn->connection, "$driver: crispr_pair - check connections are the same" );
    $crispr_pair_adaptor = $db_conn->get_adaptor( 'crisprpair' );
    isa_ok( $crispr_pair_adaptor, 'Crispr::DB::CrisprPairAdaptor', "$driver: get crispr_pair adaptor 2" );
    is( $crispr_pair_adaptor->connection, $db_conn->connection, "$driver: crispr_pair - check connections are the same 2" );
    $crispr_pair_adaptor = $db_conn->get_adaptor( 'crispr_pair_adaptor' );
    isa_ok( $crispr_pair_adaptor, 'Crispr::DB::CrisprPairAdaptor', "$driver: get crispr_pair adaptor 2" );
    is( $crispr_pair_adaptor->connection, $db_conn->connection, "$driver: crispr_pair - check connections are the same 2" );
    
    # primer
    my $primer_adaptor = $db_conn->get_adaptor( 'primer' );
    isa_ok( $primer_adaptor, 'Crispr::DB::PrimerAdaptor', "$driver: get primer adaptor" );
    is( $primer_adaptor->connection, $db_conn->connection, "$driver: primer - check connections are the same" );
    $primer_adaptor = $db_conn->get_adaptor( 'primeradaptor' );
    isa_ok( $primer_adaptor, 'Crispr::DB::PrimerAdaptor', "$driver: get primer adaptor 2" );
    is( $primer_adaptor->connection, $db_conn->connection, "$driver: primer - check connections are the same 2" );
    $primer_adaptor = $db_conn->get_adaptor( 'primer_adaptor' );
    isa_ok( $primer_adaptor, 'Crispr::DB::PrimerAdaptor', "$driver: get primer adaptor 3" );
    is( $primer_adaptor->connection, $db_conn->connection, "$driver: primer - check connections are the same 3" );
    
    # primer pair
    my $primer_pair_adaptor = $db_conn->get_adaptor( 'primer_pair' );
    isa_ok( $primer_pair_adaptor, 'Crispr::DB::PrimerPairAdaptor', "$driver: get primer_pair adaptor" );
    is( $primer_pair_adaptor->connection, $db_conn->connection, "$driver: primer_pair - check connections are the same" );
    $primer_pair_adaptor = $db_conn->get_adaptor( 'primer_pairadaptor' );
    isa_ok( $primer_pair_adaptor, 'Crispr::DB::PrimerPairAdaptor', "$driver: get primer_pair adaptor 2" );
    is( $primer_pair_adaptor->connection, $db_conn->connection, "$driver: primer_pair - check connections are the same 2" );
    $primer_pair_adaptor = $db_conn->get_adaptor( 'primer_pair_adaptor' );
    isa_ok( $primer_pair_adaptor, 'Crispr::DB::PrimerPairAdaptor', "$driver: get primer_pair adaptor 3" );
    is( $primer_pair_adaptor->connection, $db_conn->connection, "$driver: primer_pair - check connections are the same 3" );
    
    # plate
    my $plate_adaptor = $db_conn->get_adaptor( 'plate' );
    isa_ok( $plate_adaptor, 'Crispr::DB::PlateAdaptor', "$driver: get plate adaptor" );
    is( $plate_adaptor->connection, $db_conn->connection, "$driver: plate - check connections are the same" );
    $plate_adaptor = $db_conn->get_adaptor( 'plateadaptor' );
    isa_ok( $plate_adaptor, 'Crispr::DB::PlateAdaptor', "$driver: get plate adaptor 2" );
    is( $plate_adaptor->connection, $db_conn->connection, "$driver: plate - check connections are the same 2" );
    $plate_adaptor = $db_conn->get_adaptor( 'plate_adaptor' );
    isa_ok( $plate_adaptor, 'Crispr::DB::PlateAdaptor', "$driver: get plate adaptor 3" );
    is( $plate_adaptor->connection, $db_conn->connection, "$driver: plate - check connections are the same 3" );
    
    # guideRNA_prep
    my $guideRNA_prep_adaptor = $db_conn->get_adaptor( 'guideRNA_prep' );
    isa_ok( $guideRNA_prep_adaptor, 'Crispr::DB::GuideRNAPrepAdaptor', "$driver: get guideRNA_prep adaptor" );
    is( $guideRNA_prep_adaptor->connection, $db_conn->connection, "$driver: guideRNA_prep - check connections are the same" );
    $guideRNA_prep_adaptor = $db_conn->get_adaptor( 'guideRNA_prepadaptor' );
    isa_ok( $guideRNA_prep_adaptor, 'Crispr::DB::GuideRNAPrepAdaptor', "$driver: get guideRNA_prep adaptor 2" );
    is( $guideRNA_prep_adaptor->connection, $db_conn->connection, "$driver: guideRNA_prep - check connections are the same 2" );
    $guideRNA_prep_adaptor = $db_conn->get_adaptor( 'guideRNA_prep_adaptor' );
    isa_ok( $guideRNA_prep_adaptor, 'Crispr::DB::GuideRNAPrepAdaptor', "$driver: get guideRNA_prep adaptor 3" );
    is( $guideRNA_prep_adaptor->connection, $db_conn->connection, "$driver: guideRNA_prep - check connections are the same 3" );
    
    # injection pool
    my $injection_pool_adaptor = $db_conn->get_adaptor( 'injection_pool' );
    isa_ok( $injection_pool_adaptor, 'Crispr::DB::InjectionPoolAdaptor', "$driver: get injection_pool adaptor" );
    is( $injection_pool_adaptor->connection, $db_conn->connection, "$driver: injection_pool - check connections are the same" );
    $injection_pool_adaptor = $db_conn->get_adaptor( 'injection_pooladaptor' );
    isa_ok( $injection_pool_adaptor, 'Crispr::DB::InjectionPoolAdaptor', "$driver: get injection_pool adaptor 2" );
    is( $injection_pool_adaptor->connection, $db_conn->connection, "$driver: injection_pool - check connections are the same 2" );
    $injection_pool_adaptor = $db_conn->get_adaptor( 'injection_pool_adaptor' );
    isa_ok( $injection_pool_adaptor, 'Crispr::DB::InjectionPoolAdaptor', "$driver: get injection_pool adaptor 3" );
    is( $injection_pool_adaptor->connection, $db_conn->connection, "$driver: injection_pool - check connections are the same 3" );
    
    # plex
    my $plex_adaptor = $db_conn->get_adaptor( 'plex' );
    isa_ok( $plex_adaptor, 'Crispr::DB::PlexAdaptor', "$driver: get plex adaptor" );
    is( $plex_adaptor->connection, $db_conn->connection, "$driver: plex - check connections are the same" );
    $plex_adaptor = $db_conn->get_adaptor( 'plexadaptor' );
    isa_ok( $plex_adaptor, 'Crispr::DB::PlexAdaptor', "$driver: get plex adaptor 2" );
    is( $plex_adaptor->connection, $db_conn->connection, "$driver: plex - check connections are the same 2" );
    $plex_adaptor = $db_conn->get_adaptor( 'plex_adaptor' );
    isa_ok( $plex_adaptor, 'Crispr::DB::PlexAdaptor', "$driver: get plex adaptor 3" );
    is( $plex_adaptor->connection, $db_conn->connection, "$driver: plex - check connections are the same 3" );
    
    # analysis
    my $analysis_adaptor = $db_conn->get_adaptor( 'analysis' );
    isa_ok( $analysis_adaptor, 'Crispr::DB::AnalysisAdaptor', "$driver: get analysis adaptor" );
    is( $analysis_adaptor->connection, $db_conn->connection, "$driver: analysis - check connections are the same" );
    $analysis_adaptor = $db_conn->get_adaptor( 'analysisadaptor' );
    isa_ok( $analysis_adaptor, 'Crispr::DB::AnalysisAdaptor', "$driver: get analysis adaptor 2" );
    is( $analysis_adaptor->connection, $db_conn->connection, "$driver: analysis - check connections are the same 2" );
    $analysis_adaptor = $db_conn->get_adaptor( 'analysis_adaptor' );
    isa_ok( $analysis_adaptor, 'Crispr::DB::AnalysisAdaptor', "$driver: get analysis adaptor 3" );
    is( $analysis_adaptor->connection, $db_conn->connection, "$driver: analysis - check connections are the same 3" );
    
    # sample
    my $sample_adaptor = $db_conn->get_adaptor( 'sample' );
    isa_ok( $sample_adaptor, 'Crispr::DB::SampleAdaptor', "$driver: get sample adaptor" );
    is( $sample_adaptor->connection, $db_conn->connection, "$driver: sample - check connections are the same" );
    $sample_adaptor = $db_conn->get_adaptor( 'sampleadaptor' );
    isa_ok( $sample_adaptor, 'Crispr::DB::SampleAdaptor', "$driver: get sample adaptor 2" );
    is( $sample_adaptor->connection, $db_conn->connection, "$driver: sample - check connections are the same 2" );
    $sample_adaptor = $db_conn->get_adaptor( 'sample_adaptor' );
    isa_ok( $sample_adaptor, 'Crispr::DB::SampleAdaptor', "$driver: get sample adaptor 3" );
    is( $sample_adaptor->connection, $db_conn->connection, "$driver: sample - check connections are the same 3" );
    
    # sample_amplicon
    my $sample_amplicon_adaptor = $db_conn->get_adaptor( 'sample_amplicon' );
    isa_ok( $sample_amplicon_adaptor, 'Crispr::DB::SampleAmpliconAdaptor', "$driver: get sample_amplicon adaptor" );
    is( $sample_amplicon_adaptor->connection, $db_conn->connection, "$driver: sample_amplicon - check connections are the same" );
    $sample_amplicon_adaptor = $db_conn->get_adaptor( 'sample_ampliconadaptor' );
    isa_ok( $sample_amplicon_adaptor, 'Crispr::DB::SampleAmpliconAdaptor', "$driver: get sample_amplicon adaptor 2" );
    is( $sample_amplicon_adaptor->connection, $db_conn->connection, "$driver: sample_amplicon - check connections are the same 2" );
    $sample_amplicon_adaptor = $db_conn->get_adaptor( 'sample_amplicon_adaptor' );
    isa_ok( $sample_amplicon_adaptor, 'Crispr::DB::SampleAmpliconAdaptor', "$driver: get sample_amplicon adaptor 3" );
    is( $sample_amplicon_adaptor->connection, $db_conn->connection, "$driver: sample_amplicon - check connections are the same 3" );
    
    SKIP: {
        skip "methods not implemented yet!", 6;
        
        my $kasp_adaptor = $db_conn->get_adaptor( 'kasp' );
        isa_ok( $kasp_adaptor, 'Crispr::DB::KaspAdaptor', "$driver: get kasp adaptor" );
        is( $kasp_adaptor->connection, $db_conn->connection, "$driver: kasp - check connections are the same" );
        $kasp_adaptor = $db_conn->get_adaptor( 'kaspadaptor' );
        isa_ok( $kasp_adaptor, 'Crispr::DB::KaspAdaptor', "$driver: get kasp adaptor 2" );
        is( $kasp_adaptor->connection, $db_conn->connection, "$driver: kasp - check connections are the same 2" );
        $kasp_adaptor = $db_conn->get_adaptor( 'kasp_adaptor' );
        isa_ok( $kasp_adaptor, 'Crispr::DB::KaspAdaptor', "$driver: get kasp adaptor 3" );
        is( $kasp_adaptor->connection, $db_conn->connection, "$driver: kasp - check connections are the same 3" );
        
    }
    
    throws_ok { $db_conn->get_adaptor( 'cheese' ) } qr/is\snot\sa\srecognised\sadaptor\stype/, "$driver: Throws on unrecognised adaptor type";
    
    # drop database
    $db_connection->destroy();
}
