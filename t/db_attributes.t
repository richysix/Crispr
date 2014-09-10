#!/usr/bin/env perl
# DBA.t
use Test::More;
use Test::Exception;
use Readonly;

Readonly my $TESTS_FOREACH_DBC => 1 + 8 + 5 + 1;    # Number of tests in the loop
plan tests => 2 * $TESTS_FOREACH_DBC;

use TestDB;


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
    # check environment variables have been set
    if( $driver eq 'mysql' && ( !defined $ENV{MYSQL_DBNAME} || !defined $ENV{MYSQL_DBUSER} || !defined $ENV{MYSQL_DBPASS} ) ){
            warn "The following environment variables need to be set for connecting to the MySQL database!\n",
                "MYSQL_DBNAME, MYSQL_DBUSER, MYSQL_DBPASS\n";
    }
    else{
        push @db_adaptors, TestDB->new( $db_connection_params{$driver} );
    }
}

SKIP: {
    skip 'No database connections available', $TESTS_FOREACH_DBC * 2 if !@db_adaptors;
    skip 'Only one database connection available', $TESTS_FOREACH_DBC
      if @db_adaptors == 1;
}

foreach my $db_adaptor ( @db_adaptors ){
    my $driver = $db_adaptor->driver;
    my $dbh = $db_adaptor->connection->dbh;

    # check db handle object - 1 test
    isa_ok( $dbh, 'DBI::db', "$driver: check db object");
    
    # check db_params method - 8 tests
    isa_ok( $db_adaptor->db_params, 'HASH', "$driver: check db_params method" );
    is( $db_adaptor->db_params->{driver}, $db_connection_params{$driver}{driver}, "$driver: check db_params->driver" );
    is( $db_adaptor->db_params->{host}, $db_connection_params{$driver}{host}, "$driver: check db_params->host" );
    is( $db_adaptor->db_params->{port}, $db_connection_params{$driver}{port}, "$driver: check db_params->port" );
    is( $db_adaptor->db_params->{dbname}, $db_connection_params{$driver}{dbname}, "$driver: check db_params->dbname" );
    is( $db_adaptor->db_params->{user}, $db_connection_params{$driver}{user}, "$driver: check db_params->user" );
    is( $db_adaptor->db_params->{pass}, $db_connection_params{$driver}{pass}, "$driver: check db_params->pass" );
    is( $db_adaptor->db_params->{dbfile}, $db_connection_params{$driver}{dbfile}, "$driver: check db_params->dbfile" );
    
    # add some data to the db to check check_entry_exists_in_db method
    my $statement_1 = "insert into target values( NULL, 'SLC39A14', 'Zv9', '5',
        18067321, 18083466, '-1', 'zebrafish', 'y', 'ENSDARG00000090174',
        'SLC39A14', 'crispr_test', 71, NULL );";
    my $statement_2 = "insert into target values( NULL, 'SLC39A15', 'Zv9', '5',
        18067320, 18083470, '1', 'zebrafish', 'y', 'ENSDARG00000090173',
        'SLC39A15', 'crispr_test', 71, NULL );";
    
    my $sth = $dbh->prepare($statement_1);
    $sth->execute();
    $sth = $dbh->prepare($statement_2);
    $sth->execute();
    $sth->finish();
    
    # test entry now exists in db - 5 tests
    $statement = "select count(*) from target where target_name = ?;";
    is( $db_adaptor->check_entry_exists_in_db( $statement, [ 'SLC39A14' ] ), 1, "$driver: check entry exists 1" );
    is( $db_adaptor->check_entry_exists_in_db( $statement, [ 'SLC39A1' ] ), undef, "$driver: check entry exists 2" );
    $statement = "select * from target where target_name = ?;";
    is( $db_adaptor->check_entry_exists_in_db( $statement, [ 'SLC39A1' ] ), undef, "$driver: check entry exists 3" );
    
    $statement = "select count(*) from target where species = ?;";
    throws_ok{ $db_adaptor->check_entry_exists_in_db( $statement, [ 'zebrafish' ] ) }
        qr/TOO\sMANY\sITEMS/xms, "$driver: throws if count is more than 1";

    $statement = "select * from target;";
    throws_ok{ $db_adaptor->check_entry_exists_in_db( $statement, [ ] ) }
        qr/TOO\sMANY\sROWS/xms, "$driver: throws if too many rows returned";
    

    # check destroy method - 1 test
    is( $db_adaptor->destroy, 1, "$driver: destroy db" );
    
}
