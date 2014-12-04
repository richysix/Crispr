## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::DBConnection;
## use critic

# ABSTRACT: DBConnection object - A object for connecting to a MySQL/SQLite database

use warnings;
use strict;
use namespace::autoclean;
use Moose;
use Moose::Util::TypeConstraints;
use Carp;
use English qw( -no_match_vars );
use DBIx::Connector;
use Data::Dumper;
use Crispr::Config;
use Crispr::DB::TargetAdaptor;
use Crispr::DB::crRNAAdaptor;
use Crispr::DB::CrisprPairAdaptor;
use Crispr::DB::PlateAdaptor;
use Crispr::DB::Cas9Adaptor;
use Crispr::DB::Cas9PrepAdaptor;
use Crispr::DB::GuideRNAPrepAdaptor;
use Crispr::DB::PrimerAdaptor;
use Crispr::DB::PrimerPairAdaptor;

=method new

  Usage       : my $db_connection = Crispr::DBConnection->new(
                    driver => 'MYSQL'
                    host => 'HOST',
                    port => 'PORT',
                    dbname => 'DATABASE',
                    user => 'USER',
                    pass => 'PASS',
                    dbfile => 'db_file.db',
                );
  Purpose     : Constructor for creating DBConnection objects
  Returns     : Crispr::DBConnection object
  Parameters  :     driver => Str
                    host => Str
                    port => Str
                    dbname => Str
                    user => Str
                    pass => Str
                    dbfile => Str
  Throws      : If parameters are not the correct type
  Comments    : Automatically connects to the db when new is called.

=cut

=method driver

  Usage       : $self->driver();
  Purpose     : Getter for the db driver.
  Returns     : Str
  Parameters  : None
  Throws      : If driver is not either mysql or sqlite
  Comments    : 

=cut

has 'driver' => (
    is => 'ro',
    isa => enum( [ 'mysql', 'sqlite' ] ),
);

=method host

  Usage       : $self->host();
  Purpose     : Getter for the db host name.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'host' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

=method port

  Usage       : $self->port();
  Purpose     : Getter for the db port.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'port' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

=method dbname

  Usage       : $self->dbname();
  Purpose     : Getter for the database (schema) name.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'dbname' => (
    is => 'ro',
    isa => 'Str',
);

=method user

  Usage       : $self->user();
  Purpose     : Getter for the db user name.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'user' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

=method pass

  Usage       : $self->pass();
  Purpose     : Getter for the db password.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'pass' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

=method dbfile

  Usage       : $self->dbfile();
  Purpose     : Getter for the name of the SQLite database file.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'dbfile' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

=method connection

  Usage       : $self->connection();
  Purpose     : Getter for the db Connection object.
  Returns     : DBIx::Connector
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'connection' => (
    is => 'ro',
    isa => 'DBIx::Connector',
	writer => '_set_connection',    
);

=method BUILDARGS

  Usage       : 
  Purpose     : used to set object attributes from config file/environment variables/script options
  Returns     : new DBConnection object
  Parameters  : parameters supplied when new method is called
  Throws      : If the parameter is a string but it is not a filename that exists
                If a reference other than a HashRef is supplied
                If no parameters are supplied and enironment variables are not set
  Comments    : 

=cut

around BUILDARGS => sub {
    my $orig  = shift;
    my $self = shift;
    
    my $db_connection_params;
    # check the info supplied
    if( @_ == 1 ){
        if( !defined $_[0] ){
            $db_connection_params = $self->_try_environment_variables();
        }
        elsif( !ref $_[0] ){
            # assume it's a config filename and try and open it
            if( ! -e $_[0] ){
                confess join(q{ }, 'Assumed that',  $_[0], 'is a config file, but file does not exist.', ), "\n";
            }
            else{
                # load db config
                my $db_params = Crispr::Config->new($_[0]);
                
                $db_connection_params = {
                    driver => $db_params->{ driver },
                    host => $db_params->{ host },
                    port => $db_params->{ port },
                    user => $db_params->{ user },
                    pass => $db_params->{ pass },
                    dbname => $db_params->{ dbname },
                    dbfile => $db_params->{ dbfile },
                };
            }
        }
        elsif( ref $_[0] eq 'HASH' ){
            # hashref.
            $db_connection_params = $_[0];
        }
        else{
            # complain
            confess join(q{ }, "Could not parse arguments to BUILD method!\n", Dumper( $_[0] ) );
        }
    }
    elsif( @_ == 0 ){
        $db_connection_params = $self->_try_environment_variables();
    }
    elsif( @_ > 1 ){
        # assume its an array of key value pairs
        return $self->$orig( @_ );
    }
    
    return $self->$orig( $db_connection_params );
};

=method _try_environment_variables

  Usage       : 
  Purpose     : used to attempt to use environment variables if nothing else is supplied
  Returns     : 
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub _try_environment_variables {
    my ( $self ) = @_;
    
    # check environment variables
    if( !$ENV{MYSQL_DBNAME} || !$ENV{MYSQL_DBUSER} || !$ENV{MYSQL_DBPASS} ){
        confess join(q{ }, 'No config file or options supplied.',
            'Trying to connect to database using environment variables.',
            "These environment variables need to be set!\n",
            "MYSQL_DBNAME, MYSQL_DBUSER, MYSQL_DBPASS\n", ); 
    }
    # try environment variables. Assume mysql. TO DO: could try sqlite as well maybe.
    my $db_connection_params = {
        driver => 'mysql',
        dbname => $ENV{MYSQL_DBNAME},
        host => $ENV{MYSQL_DBHOST} || '127.0.0.1',
        port => $ENV{MYSQL_DBPORT} || 3306,
        user => $ENV{MYSQL_DBUSER},
        pass => $ENV{MYSQL_DBPASS},
    };
    
    return $db_connection_params;
}

=method BUILD

  Usage       : 
  Purpose     : BUILD method used to connect to the database when object is created
  Returns     : 
  Parameters  : None
  Throws      : 
  Comments    : Adds DBIx connector object to connection attribute

=cut

sub BUILD {
    my $self = shift;
    
    my $conn;
    if( !defined $self->driver ){
        confess "A valid driver (mysql or sqlite) must be specified\n";
    }
    elsif( $self->driver eq 'mysql' ){
        $conn = DBIx::Connector->new( $self->_data_source(),
                                $self->user(),
                                $self->pass(),
                                { RaiseError => 1, AutoCommit => 1 },
                                )
                                or die $DBI::errstr;
    }
    elsif( $self->driver eq 'sqlite' ){
        $conn = DBIx::Connector->new( $self->_data_source(),
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
}

=method _data_source

  Usage       : $self->_data_source();
  Purpose     : internal method to produce a data source string for connecting
                to the db.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub _data_source {
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

=method get_adaptor

  Usage       : $self->get_adaptor( 'object_type' );
  Purpose     : method to retrieve a specific adaptor type.
  Returns     : Crispr::DB::DBConnection object
  Parameters  : Str (Adaptor type)
  Throws      : If input string is not recognised.
  Comments    : Creates a new adaptor of the correct type and returns it.

=cut

sub get_adaptor {
    my ( $self, $adaptor_type, ) = @_;
    
    my %adaptor_codrefs = (
        target => 'Crispr::DB::TargetAdaptor',
        targetadaptor => 'Crispr::DB::TargetAdaptor',
        crrna => 'Crispr::DB::crRNAAdaptor',
        crrnaadaptor => 'Crispr::DB::crRNAAdaptor',
        cas9 => 'Crispr::DB::Cas9Adaptor',
        cas9adaptor => 'Crispr::DB::Cas9Adaptor',
        cas9prep => 'Crispr::DB::Cas9PrepAdaptor',
        cas9prepadaptor => 'Crispr::DB::Cas9PrepAdaptor',
        guidernaprep => 'Crispr::DB::GuideRNAPrepAdaptor',
        guidernaprepadaptor => 'Crispr::DB::GuideRNAPrepAdaptor',
        plate => 'Crispr::DB::PlateAdaptor',
        plateadaptor => 'Crispr::DB::PlateAdaptor',
        primer => 'Crispr::DB::PrimerAdaptor',
        primeradaptor => 'Crispr::DB::PrimerAdaptor',
        primerpair => 'Crispr::DB::PrimerPairAdaptor',
        primerpairadaptor => 'Crispr::DB::PrimerPairAdaptor',
        crisprpair => 'Crispr::DB::CrisprPairAdaptor',
        crisprpairadaptor => 'Crispr::DB::CrisprPairAdaptor',
    );
    
    my %args = (
        #dbname => $self->dbname,
        #connection => $self->connection,
        db_connection => $self,
    );
    
    my $internal_adaptor_type = lc( $adaptor_type );
    $internal_adaptor_type =~ s/_//xmsg;
    if( exists $adaptor_codrefs{ $internal_adaptor_type } ){
        return $adaptor_codrefs{ $internal_adaptor_type }->new( \%args );
    }
    else{
        confess "$adaptor_type is not a recognised adaptor type.\n";
    }    
}

=method db_params

  Usage       : $self->db_params();
  Purpose     : method to return the db parameters as a HashRef.
                used internally to share the db params around Adaptor objects
  Returns     : HashRef
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

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


__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 SYNOPSIS
 
    use Crispr::DB::DBConnection;
    
    # connection to a mysql database
    my $db_connection = Crispr::DB::DBConnection->new(
        driver => 'mysql',
        host => 'HOST',
        port => 'PORT',
        dbname => 'DATABASE',
        user => 'USER',
        pass => 'PASS',
    );
  
    # connection to an sqlite database
    my $db_connection = Crispr::DB::DBConnection->new(
        driver => 'sqlite',
        dbfile => 'crispr.db',
        dbname => 'crispr',
    );
    
    # get a target adaptor
    my $target_adaptor = $db_connection->get_adaptor( 'target' );

=head1 DESCRIPTION

This module is for connecting to a database to hold a single open connection to the db.
The connection to the database is established by this object upon creation and can be used to create new specific database object adaptors.
The database connection is passed from one adaptor object to another to ensure that only one connection is opened to the database.

