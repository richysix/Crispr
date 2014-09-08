package TestDB;
use Moose;
use File::Slurp;
use File::Spec;
use DBIx::Connector;

with 'Crispr::Adaptors::DBAttributes';

has data_source =>(
    is => 'rw',
    isa => 'Str',
    builder => '_build_data_source',
    lazy => 1,
);

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
    }
    else{
        confess "Invalid driver (", $self->driver, ") specified";
    }
    $self->_set_connection( $conn );
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

sub create {
    my ( $self, ) = @_;
    $self->alter_schema( 1 );
    return $self->connection;
}

sub destroy {
    my ( $self, ) = @_;
    $self->alter_schema( 0 );
    my $dbh = $self->connection->dbh;
    $dbh->disconnect;
    if ( -e 'test.db' ) {
        unlink 'test.db';
    }
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
            $sql =~ s/INT/integer/xms;
            $sql =~ s/UNSIGNED\s+AUTO_INCREMENT//xms;
            $sql =~ s/\s+ENGINE\s*=\s*\w{6}//xms;
            # remove enums
            $sql =~ s/ENUM\(.*\)//xg;
        }
        #print $sql, "\n";
        
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
