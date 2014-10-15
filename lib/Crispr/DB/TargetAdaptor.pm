## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::TargetAdaptor;
## use critic

# ABSTRACT: TargetAdaptor object - object for storing Target objects in and retrieving them from a SQL database

use namespace::autoclean;
use Moose;
use Crispr::Target;
use DateTime;
use Carp qw( cluck confess );
use English qw( -no_match_vars );

extends 'Crispr::DB::BaseAdaptor';

=method new

  Usage       : my $target_adaptor = Crispr::TargetAdaptor->new(
					dbname => 'db_name',
					connection => $connection,
                );
  Purpose     : Constructor for creating target adaptor objects
  Returns     : Crispr::TargetAdaptor object
  Parameters  :     dbname => Str,
					connection => DBIx::Connector object,
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method store_targets

  Usage       : $targets = $target_adaptor->store_targets( $targets );
  Purpose     : Store a set of targets in the database
  Returns     : ArrayRef of Crispr::Target objects
  Parameters  : ArrayRef of Crispr::Target objects
  Throws      : If argument is not an ArrayRef
                If objects in ArrayRef are not Crispr::Target objects
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None
   
=cut

sub store_targets {
    my $self = shift;
    my $targets = shift;
    my $dbh = $self->connection->dbh();
    
	confess "Supplied argument must be an ArrayRef of Target objects.\n" if( ref $targets ne 'ARRAY');
	foreach ( @{$targets} ){
        if( !ref $_ || !$_->isa('Crispr::Target') ){
            confess "Argument must be Crispr::Target objects.\n";
        }
    }
	
    my $statement = "insert into target values( ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ? );"; 
    
    $self->connection->txn(  fixup => sub {
		my $sth = $dbh->prepare($statement);
		
		foreach my $target ( @$targets ){
			$sth->execute($target->target_id, $target->target_name,
				$target->assembly, $target->chr, $target->start, $target->end, $target->strand,
				$target->species, $target->requires_enzyme,
				$target->gene_id, $target->gene_name,
				$target->requestor, $target->ensembl_version, $target->designed, );
			
			my $last_id;
			$last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'target', 'target_id' );
			$target->target_id( $last_id );
		}
		
		$sth->finish();
    } );
    
    return $targets;
}

=method store

  Usage       : $target = $target_adaptor->store( $target );
  Purpose     : Store a target in the database
  Returns     : Crispr::Target object
  Parameters  : Crispr::Target object
  Throws      : If argument is not a Target object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None

=cut

sub store {
    my ( $self, $target, ) = @_;
	# make an arrayref with this one target and call store_targets
	my @targets = ( $target );
	my $targets = $self->store_targets( \@targets );
	
	return $targets->[0];
}

=method update_designed

  Usage       : $target = $target_adaptor->update_designed( $target );
  Purpose     : Updates the designed column of the target table in the db
  Returns     : Crispr::Target object
  Parameters  : Crispr::Target object
  Throws      : If argument is not a Target object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None

=cut

sub update_designed {
    my ( $self, $target ) = @_;
    my $dbh = $self->connection->dbh();
	
	# check whether designed is defined - Makes no sense to update if it is not
	my $date;
	if( !defined $target->designed ){
		# use today's date
		my $date_obj = DateTime->now();
		$date = $date_obj->ymd;
		$target->designed( $date_obj );
	}
	else{
		$date = $target->designed;
	}
	
	my $update_st = "update target set designed = ? where target_id = ?;";
	
    $self->connection->txn(  fixup => sub {
		my $sth = $dbh->prepare($update_st);
		$sth->execute( $date, $target->target_id );
    } );
}

#sub update {
#    my $self = shift;
#    my $target = shift;
#    my $update_by = shift;
#    my $dbh = $self->connection->dbh();
#
#    my $statement = "update target set ";
#
#    if( $update_by eq 'name' ){
#	$statement = $statement .  join(" '", "target_id =", $target->target_id() ) . "', ";
#    }
#    elsif( $update_by eq 'target_id' ){
#	$statement = $statement . join(" '", "name =", $target->target_name() ) . "', ";
#    }
#    $statement = $statement . join(" '", "target =", $target->chr() ) . "', " .
#				join(" '", "target =", $target->start() ) . "', " .
#				join(" '", "target =", $target->end() ) . "', " .
#				join(" '", "target =", $target->strand() ) . "', " .
#				join(" '", "target =", $target->spacer_target_start() ) . "', " .
#				join(" '", "target =", $target->spacer_target_end() ) . "', " .
#				join(" '", "target =", $target->species() ) . "', " .
#				join(" '", "target =", $target->requires_enzyme() ) . "', " .
#				join(" '", "target =", $target->gene_id() ) . "', " .
#				join(" '", "target =", $target->gene_name() ) . "', " .
#				join(" '", "target =", $target->requestor() ) . "', " .
#				join(" '", "target =", $target->ensembl_version() ) . "', " .
#				join(" '", "target =", $target->sequence() ) . "', " .
#				join(" '", "target =", $target->date_created() ) . "', " .
#				join(" '", "target =", $target->designed() ) . "' ";
#    if( $update_by eq 'name' ){
#	$statement = $statement .  "where name = '" . $target->target_name() . "';";
#    }
#    elsif( $update_by eq 'target_id' ){
#	$statement = $statement .  "where target_id = '" . $target->target_id() . "';";
#    }
#    
#    $statement =~ s/'NULL'/ NULL/g;
#    #print $statement, "\n";
#    
#    my $sth = $dbh->prepare($statement);
#    $sth->execute();
#
#    # check if target has associated transcripts
#    if( $target->transcripts() ){
#	# get transcripts
#	my $transcripts = $target->transcripts();
#	$self->update_transcripts( $target, $transcripts, );
#    }
#    $sth->finish();
#
#    return $target;
#}
#
##sub update_transcripts {
##    my $self = shift;
##    my $target = shift;
##    my $transcript_ids = shift;
##
##    # and insert transcript ids into transcript table with target_id
##    my $statement = "update transcript set transcript" . $target->target_id() . ", ? );";
##    my $sth = $self->db_adaptor->connection->dbh->prepare($statement);
##    my @transcript_ids = split/,/, $transcript_ids;
##    foreach ( @transcript_ids ){
##	$sth->execute( $_ );
##    }
##    if( !$sth->{'Executed'} ){
##	die "Could not add transcripts for target_id:$target_id to transcript table.\n";
##    }    
##    $sth->finish();
##}

=method fetch_by_id

  Usage       : $targets = $target_adaptor->fetch_by_id( $target_id );
  Purpose     : Fetch a target given its database target id
  Returns     : Crispr::Target object
  Parameters  : crispr-db target id - Int
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_by_id {
    my ( $self, $id ) = @_;

    my $statement = "select * from target where target_id = ?;";
    my $result;
    eval{ $result = $self->fetch_rows_expecting_single_row( $statement, [ $id ] ); };
    
    my $target;
    if( $EVAL_ERROR ){
        if( $EVAL_ERROR =~ m/NO\sROWS/xms ){
    		confess "Couldn't retrieve target, $id, from database.\n";
        }
        elsif( $EVAL_ERROR =~ m/TOO\sMANY\sROWS/xms ){
            confess "Target id, $id, should be unique, but I got more than one row returned!\n";
        }
        else{
            confess $EVAL_ERROR, "\n";
        }
    }
    else{
        $target = $self->_make_new_target_from_db( $result, );
    }
    
    return $target;
}

=method fetch_by_ids

  Usage       : $targets = $target_adaptor->fetch_by_ids( \@target_ids );
  Purpose     : Fetch a list of targets given a list of db ids
  Returns     : Arrayref of Crispr::Target objects
  Parameters  : Arrayref of crispr-db target ids
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_by_ids {
    my ( $self, $ids ) = @_;
	my @targets;
    foreach my $id ( @{$ids} ){
        push @targets, $self->fetch_by_id( $id );
    }
	
    return \@targets;
}

=method fetch_by_name_and_requestor

  Usage       : $targets = $target_adaptor->fetch_by_name_and_requestor( $target_name, $requestor );
  Purpose     : Fetch a target given a target name
  Returns     : Crispr::Target object
  Parameters  : crispr-db target name - Str
                requestor - Str
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_by_name_and_requestor {
    my ( $self, $target_name, $requestor ) = @_;

    my $statement = "select * from target where target_name = ? and requestor = ?;";
    my $target;
    eval{
        my $results = $self->fetch_rows_expecting_single_row( $statement, [ $target_name, $requestor, ], );
        $target = $self->_make_new_target_from_db( $results );
    };
    if( $EVAL_ERROR ){
        if( $EVAL_ERROR eq 'NO ROWS' ){
            confess "Couldn't retrieve target, $target_name, from database.\n";
        }
        elsif( $EVAL_ERROR eq 'TOO MANY ROWS' ){
            confess "Target name, $target_name, should be unique, but I got more than one row returned!\n";
        }
        else{
            confess "$target_name: $EVAL_ERROR\n";
        }
    }
    
    return $target;
}

=method fetch_by_names_and_requestors

  Usage       : $targets = $target_adaptor->fetch_by_names_and_requestors( \@target_names_and_requestors );
  Purpose     : Fetch a list of targets given a list of db target names
  Returns     : Arrayref of Crispr::Target objects
  Parameters  : Arrayref of Arrayrefs containg crispr-db target names and requestors
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_by_names_and_requestors {
    my ( $self, $names_and_requestors ) = @_;
	my @targets;
    
    foreach my $info ( @{$names_and_requestors} ){
        my $target = $self->fetch_by_name_and_requestor( @{$info} );
        push @targets, $target;
    }
	
    return \@targets;
}

=method fetch_by_crRNA

  Usage       : $targets = $target_adaptor->fetch_by_crRNA( $crRNA );
  Purpose     : Fetch a target given a crRNA object
  Returns     : Crispr::Target object
  Parameters  : Crispr::crRNA object
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_by_crRNA {
	my ( $self, $crRNA, ) = @_;
    my $dbh = $self->connection->dbh();
	
	# try to retrieve target by id first then name
    my $target;
    if( defined $crRNA->target_id ){
        $target = $self->fetch_by_id( $crRNA->target_id );
        
    }
    elsif( defined $crRNA->target_name &&
            defined $crRNA->requestor ){
        $target = $self->fetch_by_name_and_requestor( $crRNA->target_name, $crRNA->requestor );
    }
    
    return $target;
}

=method fetch_by_single_attribute

  Usage       : $targets = $target_adaptor->fetch_by_single_attribute( $statement, $attribute );
  Purpose     : Fetch a target given an SQL statement and a parameter
  Returns     : Crispr::Target object
  Parameters  : SQL statement - Str
                statement parameter - Str
  Throws      : If no rows are returned from the database
                If too many rows are returned from the database
  Comments    : The where clause in the SQL statement must take only one bind variable

=cut

sub fetch_by_single_attribute {
	my ( $self, $statement, $attribute, ) = @_;
    my $dbh = $self->connection->dbh();
    my $sth = $dbh->prepare($statement);
    $sth->execute( $attribute );
    
    my $target;
	my $num_rows = 0;
	while( my @fields = $sth->fetchrow_array ){
		$num_rows++;
		$target = $self->_make_new_target_from_db( \@fields, );
	}
    
    if( $num_rows == 0 ){
		die 'NO ROWS';
    }
    elsif( $num_rows > 1 ){
		die 'TOO MANY ROWS';
    }
    if( !defined $target ){
        die 'TARGET UNDEF';
    }
    
    return $target;
}

#_make_new_object_from_db
#
#Usage       : $target = $self->_make_new_object_from_db( \@fields );
#Purpose     : Create a new object from a db entry
#Returns     : Crispr::Target object
#Parameters  : ArrayRef of Str
#Throws      : 
#Comments    : This method is required when consuming the DBAttributes Role.

sub _make_new_object_from_db {
    my ( $self, $fields ) = @_;
    return $self->_make_new_target_from_db( $fields );
}

#_make_new_target_from_db
#
#Usage       : $target = $self->_make_new_target_from_db( \@fields );
#Purpose     : Create a new Crispr::Target object from a db entry
#Returns     : Crispr::Target object
#Parameters  : ArrayRef of Str
#Throws      : 
#Comments    :

sub _make_new_target_from_db {
    my ( $self, $fields ) = @_;
    my $target;
	
	my %bool_for = (
		y => 1,
		n => 0,
        1 => 1,
        0 => 0,
	);
	
	my %args = (
		target_id => $fields->[0],
		target_name => $fields->[1],
		start => $fields->[4],
		end => $fields->[5],
		strand => $fields->[6],
		requires_enzyme => $bool_for{$fields->[8]},
		requestor => $fields->[11],
	);
	$args{ 'assembly' } = $fields->[2] if( defined $fields->[2] );
	$args{ 'chr' } = $fields->[3] if( defined $fields->[3] );
	$args{ 'species' } = $fields->[7] if( defined $fields->[7] );
	$args{ 'gene_id' } = $fields->[9] if( defined $fields->[9] );
	$args{ 'gene_name' } = $fields->[10] if( defined $fields->[10] );
	$args{ 'ensembl_version' } = $fields->[12] if( defined $fields->[12] );
	$args{ 'designed' } = $fields->[13] if( defined $fields->[13] );
	
	$target = Crispr::Target->new( %args );
    $target->target_adaptor( $self );
	
    return $target;
}

#sub fetch_all_by_date {
#	my ( $self, $date ) = @_;
#	my $statement = "select * from target where date_created = ?";
#	
#    my $dbh = $self->connection->dbh();
#    my @targets;
#    $self->connection->txn(  fixup => sub {
#	my $sth = $dbh->prepare($statement);
#	my $num_rows;
#    $num_rows = $sth->execute( $date );
#	
#	if( $num_rows == 0 ){
#	    die "There are no targets created on ", $date, ".\n";
#	}
#	else{
#	    while( my @fields = $sth->fetchrow_array ){
#			my $target = $self->_make_new_target_from_db( \@fields, );
#		push @targets, $target;
#	    }
#	}
#    } );
#    
#    return \@targets;
#}
#
#
######################################################################################
##    fetch_targets_without_designs
##
##    Usage       : $targets = $target_adaptor->fetch_targets_without_designs( $limit );
##    Purpose     : Fetch a list of targets that do not have talen pair designs
##		  ordered by creation date
##    Returns     : Arrayref of Crispr::Target objects
##    Parameters  : limit (optional) - number of targets to return
##    Throws      : If no rows are returned from the database
##    Comments    : None
##
######################################################################################
#
#sub fetch_targets_without_designs {
#    my ( $self, $limit ) = @_;
#    my $statement;
#    if( $limit ){
#	$statement = "select * from target where designed = 'n' order by date_created limit ?;";
#    }
#    else{
#	$statement = "select * from target where designed = 'n' order by date_created;";
#    }
#    
#    my $dbh = $self->connection->dbh();
#    my @targets;
#    $self->connection->txn(  fixup => sub {
#	my $sth = $dbh->prepare($statement);
#	my $num_rows;
#	if( $limit ){
#	    $num_rows = $sth->execute( $limit );
#	}
#	else{
#	    $num_rows = $sth->execute();
#	}
#	
#	if( $num_rows == 0 ){
#	    die "There are no targets without talen designs.\n";
#	}
#	else{
#	    while( my @fields = $sth->fetchrow_array ){
#		my $target = $self->_make_new_target_from_db( \@fields, );
#		push @targets, $target;
#	    }
#	}
#    } );
#    
#    return \@targets;
#}

#sub _db_error_handling{
#    my $self = shift;
#    my $target = shift;
#    my $error_msg = shift;
#    
#    if( $error_msg =~ m /Duplicate entry/ && $error_msg =~ m /key 'name'/ ){
#	warn "Target name already exists in the database... \nUpdating...\n";
#	$self->update( $target, 'name' );
#    }
#}

sub delete_target_from_db {
	my ( $self, $target ) = @_;
	
	# first check target exists in db
	
	# delete primers and primer pairs
	
	# delete transcripts
	
	# if target has talen pairs, delete tale and talen pairs
	
	
	
}


=method driver

  Usage       : $self->driver();
  Purpose     : Getter for the db driver.
  Returns     : Str
  Parameters  : None
  Throws      : If driver is not either mysql or sqlite
  Comments    : 

=cut

=method host

  Usage       : $self->host();
  Purpose     : Getter for the db host name.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method port

  Usage       : $self->port();
  Purpose     : Getter for the db port.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method dbname

  Usage       : $self->dbname();
  Purpose     : Getter for the database (schema) name.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method user

  Usage       : $self->user();
  Purpose     : Getter for the db user name.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method pass

  Usage       : $self->pass();
  Purpose     : Getter for the db password.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method dbfile

  Usage       : $self->dbfile();
  Purpose     : Getter for the name of the SQLite database file.
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method connection

  Usage       : $self->connection();
  Purpose     : Getter for the db Connection object.
  Returns     : DBIx::Connector
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

=method db_params

  Usage       : $self->db_params();
  Purpose     : method to return the db parameters as a HashRef.
                used internally to share the db params around Adaptor objects
  Returns     : HashRef
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

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

=method fetch_rows_for_generic_select_statement

  Usage       : $self->fetch_rows_for_generic_select_statement( $sql_statement, $parameters );
  Purpose     : method to execute a generic select statement and return the rows from the db.
  Returns     : ArrayRef[Str]
  Parameters  : MySQL statement (Str)
                Parameters (ArrayRef)
  Throws      : If no rows are returned from the database.
  Comments    : 

=cut

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

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod
 
=head1 SYNOPSIS
 
    use Crispr::DB::DBAdaptor;
    my $db_adaptor = Crispr::DB::DBAdaptor->new(
        host => 'HOST',
        port => 'PORT',
        dbname => 'DATABASE',
        user => 'USER',
        pass => 'PASS',
        connection => $dbc,
    );
  
    my $target_adaptor = $db_adaptor->get_adaptor( 'target' );
    
    # store a target object in the db
    $target_adaptor->store( $target );
    
    # retrieve a target by id or name/requestor
    my $target = $target_adaptor->fetch_by_id( '214' );
  
    # retrieve a target by combination of name and requestor
    my $target = $target_adaptor->fetch_by_name_and_requestor( 'ENSDARG0000124562', 'crispr_test' );
    

=head1 DESCRIPTION
 
 A TargetAdaptor is an object used for storing and retrieving Target objects in an SQL database.
 The recommended way to use this module is through the DBAdaptor object as shown above.
 This allows a single open connection to the database which can be shared between multiple database adaptors.
 
=head1 DIAGNOSTICS
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
=head1 DEPENDENCIES
 
 
=head1 INCOMPATIBILITIES
 
