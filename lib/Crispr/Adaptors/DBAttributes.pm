package Crispr::Adaptors::DBAttributes;
use namespace::autoclean;
use Moose::Role;
use Moose::Util::TypeConstraints;
use English qw( -no_match_vars );

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
    while( my @fields = $sth->fetchrow_array ){
        $num_rows++;
        if( $fields[0] == 1 ){
            $exists = 1;
        }
        elsif( $fields[0] > 1 ){
            die "TOO MANY ITEMS";
        }
    }
    if( $num_rows != 1 ){
        confess "TOO MANY ROWS";
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
    
    return $result;
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

my %reports_for = (
    'Crispr::Adaptors::crRNAAdaptor' => {
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




1;

=head1 NAME
 
<DB::DBAttributes> - Role to add attributes and methods to MySQL Database Adaptor
 
 
=head1 VERSION
 
This documentation refers to <DB::DBAttributes> version 0.1
 
 
=head1 SYNOPSIS
 
    with 'DB::DBAttributes';
  
  
=head1 DESCRIPTION
 
This module is a Moose Role used to add attributes to Mysql Database Adaptors.
The attributes added are:

=over

=item *     host        - The host that the database is on
 
=item *     port        - port number to connect on

=item *     dbname      - database name

=item *     user        - username

=item *     pass        - password

=item *     connection  - attribute to hold a DBIx::Connector object

=back
 
