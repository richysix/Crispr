## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::BaseAdaptor;
## use critic

# ABSTRACT: BaseAdaptor object - Parent Class for objects adaptor for a MySQL/SQLite database

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

=method new

  Usage       : my $db_adaptor = Crispr::BaseAdaptor->new(
                    db_connection => $db_connection,
                );
  Purpose     : Constructor for creating BaseAdaptor objects
  Returns     : Crispr::BaseAdaptor object
  Parameters  :     db_connection => Crispr::DB::DBConnection object,
  Throws      : If parameters are not the correct type
  Comments    : 

=cut

=method db_connection

  Usage       : $self->db_connection();
  Purpose     : Getter for the db Connection object.
  Returns     : Crispr::DB::DBConnection
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'db_connection' => (
    is => 'ro',
    isa => 'Crispr::DB::DBConnection',
    handles => {
        dbname => 'dbname',
        connection => 'connection',
    },
);

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

sub _prepare_sql {
    my ( $self, $sql, $where_clause, $where_parameters ) = @_;
    my $dbh = $self->connection->dbh();
    
    my $sth = $dbh->prepare($sql);

    # Bind any parameters
    if ($where_clause) {
        if( !defined $where_parameters ){
            confess "Parameters must be supplied with a where clause!\n";
        }
        elsif ( ref $where_parameters eq 'ARRAY' ) {
            my $param_num = 0;
            while ( @{$where_parameters} ) {
                $param_num++;
                my $value = shift @{$where_parameters};
                $sth->bind_param( $param_num, $value );
            }
        }
        else{
            confess "Parameters to the where clause must be supplied as an ArrayRef!\n";
        }
    }
    
    return $sth;
}

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

=head1 DESCRIPTION

This is the parent class for all database adaptors.
It has an attribute for the already open database connection (Crispr::DB::DBConnection).
It also provides a set of common database methods that can be used by all adaptor objects.

