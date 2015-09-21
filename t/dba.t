#!/usr/bin/env perl
# DBA.t
use warnings;
use strict;

use Test::More;
use Readonly;
use English qw( -no_match_vars );

Readonly my $TESTS_FOREACH_DBC => 1 + 1 + 8;    # Number of tests in the loop
if( $ENV{NO_DB} ) {
    plan skip_all => 'Not testing database';
}
else {
    plan tests => 2 * $TESTS_FOREACH_DBC;
}

use lib 't/lib';
use TestMethods;

my $test_method_obj = TestMethods->new();
my ( $db_connection_params, $db_connections ) = $test_method_obj->create_test_db();

SKIP: {
    skip 'No database connections available', $TESTS_FOREACH_DBC * 2 if !@{$db_connections};
    skip 'Only one database connection available', $TESTS_FOREACH_DBC
      if @{$db_connections} == 1;
}

foreach my $db_adaptor ( @{$db_connections} ){
    my $driver = $db_adaptor->driver;
    my $dbh = $db_adaptor->connection->dbh;

    # check db handle object - 1 test
    isa_ok( $dbh, 'DBI::db', "$driver: check db object");
    
    # check destroy method - 1 test
    is( $db_adaptor->destroy, 1, "$driver: destroy db" );
    
    # check db_params method - 8 tests
    isa_ok( $db_adaptor->db_params, 'HASH', "$driver: check db_params method" );
    is( $db_adaptor->db_params->{driver}, $db_connection_params->{$driver}{driver}, "$driver: check db_params->driver" );
    is( $db_adaptor->db_params->{host}, $db_connection_params->{$driver}{host}, "$driver: check db_params->host" );
    is( $db_adaptor->db_params->{port}, $db_connection_params->{$driver}{port}, "$driver: check db_params->port" );
    is( $db_adaptor->db_params->{dbname}, $db_connection_params->{$driver}{dbname}, "$driver: check db_params->dbname" );
    is( $db_adaptor->db_params->{user}, $db_connection_params->{$driver}{user}, "$driver: check db_params->user" );
    is( $db_adaptor->db_params->{pass}, $db_connection_params->{$driver}{pass}, "$driver: check db_params->pass" );
    is( $db_adaptor->db_params->{dbfile}, $db_connection_params->{$driver}{dbfile}, "$driver: check db_params->dbfile" );
}
