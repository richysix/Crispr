## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::DBAdaptor;
## use critic

# ABSTRACT: DBAdaptor object - A object for connecting to a MySQL/SQLite database

use warnings;
use strict;
use namespace::autoclean;
use Moose;
use Moose::Util::TypeConstraints;
use Carp;
use English qw( -no_match_vars );
use DBIx::Connector;
use Data::Dumper;
use Crispr::DB::TargetAdaptor;
use Crispr::DB::Cas9PrepAdaptor;
use Crispr::Config;

=method new

  Usage       : my $db_adaptor = Crispr::DBAdaptor->new(
                    driver => 'MYSQL'
                    host => 'HOST',
                    port => 'PORT',
                    dbname => 'DATABASE',
                    user => 'USER',
                    pass => 'PASS',
                    dbfile => 'db_file.db',
                );
  Purpose     : Constructor for creating DBAdaptor objects
  Returns     : Crispr::DBAdaptor object
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
  Returns     : new DBAdaptor object
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
  Returns     : Crispr::DB::DBAdaptor object
  Parameters  : Str (Adaptor type)
  Throws      : If input string is not recognised.
  Comments    : Creates a new adaptor of the correct type and returns it.

=cut

sub get_adaptor {
    my $self = shift;
    my $adaptor_type = shift;
    
    my %adaptor_codrefs = (
        target => \&_target,
        targetadaptor => \&_target,
        cas9prep => \&_cas9_prep,
        cas9prepadaptor => \&_cas9_prep,
    );
    
    my $internal_adaptor_type = lc( $adaptor_type );
    $internal_adaptor_type =~ s/_//xmsg;
    if( exists $adaptor_codrefs{ lc $internal_adaptor_type } ){
        $adaptor_codrefs{ lc $internal_adaptor_type }->( $self, );
    }
    else{
        die "$adaptor_type is not a recognised adaptor type.\n";
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

=method check_entry_exists_in_db

  Usage       : $self->check_entry_exists_in_db( $check_statement, $params );
  Purpose     : method used to check whether a particular entry exists in the database.
                Takes a MySQL statement of the form select count(*) from table where condition = ?;'
                and parameters
  Returns     : 1 if entry exists, undef if not
  Parameters  : check statement (Str)
                statement parameters (ArrayRef[Str])
  Throws      : 
  Comments    : 

=cut

sub check_entry_exists_in_db {
    # expects check statement of the form 'select count(*) from table where condition = ?;'
    my ( $self, $check_statement, $params ) = @_;
    my $dbh = $self->connection->dbh();
    my $exists;
    
    my $sth = $dbh->prepare( $check_statement );
    $sth->execute( @{$params} );
    my $num_rows = 0;
    my @rows;
    while( my @fields = $sth->fetchrow_array ){
        push @rows, \@fields;
    }
    if( scalar @rows > 1 ){
        confess "TOO MANY ROWS";
    }
    elsif( scalar @rows == 1 ){
        if( $rows[0]->[0] == 1 ){
            $exists = 1;
        }
        elsif( $rows[0]->[0] > 1 ){
            confess "TOO MANY ITEMS";
        }
    }
    
    return $exists;
}

=method fetch_rows_expecting_single_row

  Usage       : $self->fetch_rows_expecting_single_row( $sql_statement, $parameters );
  Purpose     : method to fetch a row from the database where the result should be unique.
  Returns     : ArrayRef
  Parameters  : MySQL statement (Str)
                Parameters (ArrayRef)
  Throws      : If no rows are returned from the database.
                If more than one row is returned.
  Comments    : 

=cut

sub fetch_rows_expecting_single_row {
	my ( $self, $statement, $params, ) = @_;
    
    my $result;
    eval{
        $result = $self->fetch_rows_for_generic_select_statement( $statement, $params, );
    };
    
    if( $EVAL_ERROR ){
        if( $EVAL_ERROR =~ m/NO\sROWS/xms ){
            die 'NO ROWS';
        }
        else{
            die "An unexpected problem occured. $EVAL_ERROR\n";
        }
    }
    if( scalar @$result > 1 ){
		die 'TOO MANY ROWS';
    }
    
    return $result->[0];
}

=method fetch_rows_for_generic_select_statement

  Usage       : $self->fetch_rows_for_generic_select_statement( $sql_statement, $parameters );
  Purpose     : method to execute a generic select statement and return the rows from the db.
  Returns     : ArrayRef[Str]
  Parameters  : MySQL statement (Str)
                Parameters (ArrayRef)
  Throws      : If no rows are returned from the database.
  Comments    : 

=cut

sub fetch_rows_for_generic_select_statement {
	my ( $self, $statement, $params, ) = @_;
    my $dbh = $self->connection->dbh();
    my $sth = $dbh->prepare($statement);
    $sth->execute( @{$params} );
    
    my $results = [];
	while( my @fields = $sth->fetchrow_array ){
		push @$results, \@fields;
	}
    if( scalar @$results == 0 ){
		die 'NO ROWS';
    }
    return $results;
}

=method _target

  Usage       : $self->_target;
  Purpose     : internal method to retrieve a Target Adaptor.
  Returns     : Crispr::DB::TargetAdaptor object
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub _target { my $self = shift; return Crispr::DB::TargetAdaptor->new( $self->db_params, ); }

=method _cas9_prep

  Usage       : $self->_cas9_prep;
  Purpose     : internal method to retrieve a Target Adaptor.
  Returns     : Crispr::DB::TargetAdaptor object
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub _cas9_prep { my $self = shift; return Crispr::DB::Cas9PrepAdaptor->new( $self->db_params, ); }



my %reports_for = (
    'Crispr::DB::crRNAAdaptor' => {
        'NO ROWS'   => "crRNA does not exist in the database.",
        'ERROR'     => "crRNAAdaptor ERROR",
    },
    
);

=method _db_error_handling

  Usage       : $self->_db_error_handling( $error_message, $SQL_statement, $parameters );
  Purpose     : internal method to deal with error messages from the database.
  Returns     : Throws an exception that depends on the Adaptor type and
                the error message.
  Parameters  : Error Message (Str)
                MySQL statement (Str)
                Parameters (ArrayRef)
  Throws      : 
  Comments    : 

=cut

sub _db_error_handling{
    my ( $self, $error_msg, $statement, $params,  ) = @_;
    
    if( exists $reports_for{ ref $self } ){
        my ( $error, $message );
        if( $error_msg =~ m/\A([A-Z[:space:]]+)\sat/xms ){
            $error = $1;
            $message = $reports_for{ ref $self }->{$error};
        }
        else{
            $message = $error_msg;
        }
        die join("\n", $message,
            $statement,
            'Params: ', join(",", @{$params} ),
            ), "\n";
    }
    else{
        die join("\n", ref $self,
                        $statement,
                        'Params: ', join(",", @{$params} ),
            ), "\n";
    }
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 SYNOPSIS
 
    use Crispr::DB::DBAdaptor;
    
    # adaptor for a mysql database
    my $db_adaptor = Crispr::DB::DBAdaptor->new(
        driver => 'mysql',
        host => 'HOST',
        port => 'PORT',
        dbname => 'DATABASE',
        user => 'USER',
        pass => 'PASS',
    );
  
    # adaptor for a sqlite database
    my $db_adaptor = Crispr::DB::DBAdaptor->new(
        driver => 'sqlite',
        dbfile => 'crispr.db',
    );
  
=head1 DESCRIPTION

This module is for connecting to a database to hold a single open connection to the db.
The adaptor connects to the database upon creation and can be used to create new specific object adaptors.
The database connection is passed from one adaptor object to another to ensure that only one connection is opened to the database.
It also provides a set of common database methods that can be used by all adaptor objects.

