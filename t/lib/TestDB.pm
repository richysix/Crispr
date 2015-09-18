package TestDB;
use Moose;
use Moose::Util::TypeConstraints;
use File::Slurp;
use File::Spec;
use DBIx::Connector;

has 'driver' => (
    is => 'ro',
    isa => enum( [ 'mysql', 'sqlite' ] ),
);

has 'host' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

has 'port' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

has 'dbname' => (
    is => 'ro',
    isa => 'Str',
);

has 'user' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

has 'pass' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

has 'dbfile' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

has 'connection' => (
    is => 'ro',
    isa => 'DBIx::Connector',
	writer => '_set_connection',    
);

has 'data_source' => (
    is => 'rw',
    isa => 'Str',
    builder => '_build_data_source',
    lazy => 1,
);

has 'debug' => (
    is => 'rw',
    isa => 'Int',
    default => 0,
);

around BUILDARGS => sub {
    my $orig  = shift;
    my $self = shift;
    
    my $db_conn_params;
    my %db_connection_params = (
        mysql => {
            driver => 'mysql',
            dbname => $ENV{MYSQL_DBNAME},
            host => $ENV{MYSQL_DBHOST},
            port => $ENV{MYSQL_DBPORT},
            user => $ENV{MYSQL_DBUSER},
            pass => $ENV{MYSQL_DBPASS},
        },
        sqlite => {
            driver => 'sqlite',
            dbfile => 'test.db',
            dbname => 'test',
        }
    );
    
    if( @_ == 1 ){
        # if it's not defined die
        if( !defined $_[0] ){
            die "No parameters were supplied when creating the TestDB object!";
        }
        # if it's a scalar assume it's a driver name and try and use the defaults
        elsif( !ref $_[0] ){
            if( !exists $db_connection_params{$_[0]} ){
            }
            else{
                if( $_[0] eq 'mysql' ){
                    if( !$ENV{MYSQL_DBNAME} || !$ENV{MYSQL_DBHOST} ||
                       !$ENV{MYSQL_DBPORT} || !$ENV{MYSQL_DBUSER} ||
                       !$ENV{MYSQL_DBPASS} ){
                        die "ENVIRONMENT VARIABLES";
                    }
                    else{
                        $db_conn_params = $db_connection_params{'mysql'};
                    }
                }
                elsif( $_[0] eq 'sqlite' ){
                    $db_conn_params = $db_connection_params{'sqlite'};
                }
                else{
                    die "Could not understand the parameter passed to TestDB.\n",
                        "Expecting one of mysql or sqlite\n";
                }
            }
        }
        elsif( ref $_[0] eq 'HASH' ){
            # hashref.
            $db_conn_params = $_[0];
        }
        else{
            # complain
            die join(q{ }, "Could not parse arguments to TestDB BUILD method!\n", Dumper( $_[0] ) );
        }
    }
    elsif( @_ == 0 ){
        die "No parameters were supplied when creating the TestDB object!";
    }
    elsif( @_ > 1 ){
        # assume its an array of key value pairs
        return $self->$orig( @_ );
    }
    
    return $self->$orig( $db_conn_params );
};

sub BUILD {
    my $self = shift;
    
    my $conn;
    if( $self->driver eq 'mysql' ){
        $conn = DBIx::Connector->new( $self->data_source(),
                                $self->user(),
                                $self->pass(),
                                { RaiseError => 1, AutoCommit => 1 },
                                )
                                or die $DBI::errstr;
        $self->_set_connection( $conn );
    }
    elsif( $self->driver eq 'sqlite' ){
        $conn = DBIx::Connector->new( $self->data_source(),
                                q{},
                                q{},
                                { RaiseError => 1, AutoCommit => 1 },
                                )
                                or die $DBI::errstr;
        $self->_set_connection( $conn );
    }
    else{
        confess "Invalid driver (", $self->driver, ") specified";
    }
    $self->create();
}

sub _build_data_source {
    my $self = shift;
    
    if( $self->driver eq 'mysql' ){
        return join(":", 'DBI', 'mysql',
                    join(";", join("=", 'database', $self->dbname(), ),
                            join("=", 'host', $self->host(), ),
                            join("=", 'port', $self->port(), ), ),
                );
    }
    elsif( $self->driver eq 'sqlite' ){
        return join(":", 'DBI', 'SQLite',
                    join(";", join("=", 'dbname', $self->dbfile(), ), )
                );
    }
}

sub db_params {
    my ( $self, ) = @_;
	my %db_params = (
        'driver' => $self->driver,
		'host' => $self->host,
		'port' => $self->port,
		'dbname' => $self->dbname,
		'user' => $self->user,
		'pass' => $self->pass,
        'dbfile' => $self->dbfile,
		'connection' => $self->connection,
	);
    return \%db_params;
}

sub create {
    my ( $self, ) = @_;
    $self->alter_schema( 1 );
    return $self->connection;
}

sub disconnect {
    my ( $self, ) = @_;
    my $dbh = $self->connection->dbh;
    $dbh->disconnect;
}

sub destroy {
    my ( $self, ) = @_;
    $self->alter_schema( 0 );
    my $dbh = $self->connection->dbh;
    $dbh->disconnect;
    if ( $self->driver eq 'sqlite' && -e 'test.db' ) {
        unlink 'test.db';
    }
    return 1;
}

sub alter_schema {
    my ( $self, $create_tables ) = @_;
    my $dbh = $self->connection->dbh();
    
    if( $self->driver eq 'mysql' ){
        my $drop_st = 'DROP DATABASE IF EXISTS ' . $self->dbname . ';';
        $dbh->do( $drop_st );
        my $create_st = 'CREATE DATABASE ' . $self->dbname . ';';
        $dbh->do( $create_st );
        my $use_st = 'use ' . $self->dbname . ';';
        $dbh->do( $use_st );
    }
    
    my $schema_file = File::Spec->catfile( 'sql', 'schema_mysql.sql' );
    my $schema = read_file($schema_file);
    $schema =~ s/;\s*\z//xms;    # Remove last semi-colon so no empty statement
    my @all_sql = split( /;/, $schema );

    foreach my $sql (@all_sql) {
        
        # Convert MySQL syntax to SQLite?
        if ( $self->driver eq 'sqlite' ) {
            $sql =~ s/[A-Z]*[\sLYMG]INT\s/ integer /xmsg;
            $sql =~ s/UNSIGNED\s/ /xmsg;
            $sql =~ s/AUTO_INCREMENT\s/ /xmsg;
            $sql =~ s/\s+ENGINE\s*=\s*\w{6}//xms;
            $sql =~ s/ENUM\(.*\)//xg; # remove enums
            $sql =~ s/\z/;/xmsg; # add semi-colon
        }
        if( $self->debug == 1 ){
            print $sql, "\n";
        }
        
        # Drop table if already exists
        if ( $sql =~ m/CREATE\s+TABLE\s+(\w+)\s+/xmsi ) {
            $dbh->do("DROP TABLE IF EXISTS $1");
            
            # Just in case tmp table got left behind during failed test
            $dbh->do( 'DROP TABLE IF EXISTS ' . $1 . '_tmp' );
        }
        
        # Create table if required
        if ( $create_tables ) {
            $dbh->do($sql);
        }
    }
    
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
