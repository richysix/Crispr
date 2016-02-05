## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::GuideRNAPrepAdaptor;
## use critic

# ABSTRACT: GuideRNAPrepAdaptor object - object for storing GuideRNAPrep objects in and retrieving them from a SQL database

use namespace::autoclean;
use Moose;
use DateTime;
use Carp qw( cluck confess );
use English qw( -no_match_vars );
use Crispr::DB::GuideRNAPrep;
use Crispr::crRNA;

extends 'Crispr::DB::BaseAdaptor';

=method new

  Usage       : my $guideRNA_prep_adaptor = Crispr::DB::GuideRNAPrepAdaptor->new(
					db_connection => $db_connection,
                );
  Purpose     : Constructor for creating guideRNA_prep adaptor objects
  Returns     : Crispr::DB::GuideRNAPrepAdaptor object
  Parameters  :     db_connection => Crispr::DB::DBConnection object,
  Throws      : If parameters are not the correct type
  Comments    : The preferred method for constructing a GuideRNAPrepAdaptor is to use the
                get_adaptor method with a previously constructed DBConnection object

=cut

=method store

  Usage       : $guideRNA_prep = $guideRNA_prep_adaptor->store( $guideRNA_prep );
  Purpose     : Store a guideRNA_prep object in the database
  Returns     : Crispr::DB::GuideRNAPrep object
  Parameters  : Crispr::DB::GuideRNAPrep object
  Throws      : If argument is not a GuideRNAPrep object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : 

=cut

sub store {
    my ( $self, $guideRNA_prep, ) = @_;
	# make an arrayref with this one guideRNA_prep and call store_guideRNA_preps
	my $guideRNA_preps = $self->store_guideRNA_preps( [ $guideRNA_prep ] );
	
	return $guideRNA_preps->[0];
}

=method store_guideRNA_prep

  Usage       : $guideRNA_prep = $guideRNA_prep_adaptor->store_guideRNA_prep( $guideRNA_prep );
  Purpose     : Store a guideRNA_prep in the database
  Returns     : Crispr::DB::GuideRNAPrep object
  Parameters  : Crispr::DB::GuideRNAPrep object
  Throws      : If argument is not a GuideRNAPrep object
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : Synonym for store

=cut

sub store_guideRNA_prep {
    my ( $self, $guideRNA_prep, ) = @_;
	return $self->store( $guideRNA_prep );
}

=method store_guideRNA_preps

  Usage       : $guideRNA_preps = $guideRNA_prep_adaptor->store_guideRNA_preps( $guideRNA_preps );
  Purpose     : Store a set of guideRNA_preps in the database
  Returns     : ArrayRef of Crispr::DB::GuideRNAPrep objects
  Parameters  : ArrayRef of Crispr::DB::GuideRNAPrep objects
  Throws      : If argument is not an ArrayRef
                If objects in ArrayRef are not Crispr::DB::GuideRNAPrep objects
                If there is an error during the execution of the SQL statements
                    In this case the transaction will be rolled back
  Comments    : None
   
=cut

sub store_guideRNA_preps {
    my ( $self, $guideRNA_preps, ) = @_;
    my $dbh = $self->connection->dbh();
    
	confess "Supplied argument must be an ArrayRef of GuideRNAPrep objects.\n" if( ref $guideRNA_preps ne 'ARRAY');
	foreach ( @{$guideRNA_preps} ){
        if( !ref $_ || !$_->isa('Crispr::DB::GuideRNAPrep') ){
            confess "Argument must be Crispr::DB::GuideRNAPrep objects.\n";
        }
    }
	
    my $statement = "insert into guideRNA_prep values( ?, ?, ?, ?, ?, ?, ?, ? );"; 
    
    $self->connection->txn(  fixup => sub {
		my $sth = $dbh->prepare($statement);
		
		foreach my $guideRNA_prep ( @$guideRNA_preps ){
            my $well_id;
            my $plate_id;
            if( defined $guideRNA_prep->well ){
                $well_id = $guideRNA_prep->well->position;
                if( defined $guideRNA_prep->well->plate ){
                    $plate_id = $guideRNA_prep->well->plate->plate_id;
                }
            }
            
			$sth->execute($guideRNA_prep->db_id, $guideRNA_prep->crRNA_id,
				$guideRNA_prep->type, $guideRNA_prep->stock_concentration,
				$guideRNA_prep->made_by, $guideRNA_prep->date,
				$plate_id, $well_id,
            );
			
			my $last_id;
			$last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'guideRNA_prep', 'guideRNA_prep_id' );
			$guideRNA_prep->db_id( $last_id );
		}
		
		$sth->finish();
    } );
    
    return $guideRNA_preps;
}

=method fetch_by_id

  Usage       : $guideRNA_prep = $guideRNA_prep_adaptor->fetch_by_id( $guideRNA_prep_id );
  Purpose     : Fetch a guideRNA_prep given its database id
  Returns     : Crispr::DB::GuideRNAPrep object
  Parameters  : crispr-db guideRNA_prep_id - Int
  Throws      : If no rows are returned from the database
  Comments    : None

=cut

sub fetch_by_id {
    my ( $self, $id ) = @_;

    my $guideRNA_prep = $self->_fetch( 'guideRNA_prep_id = ?', [ $id ] )->[0];
    
    if( !$guideRNA_prep ){
        confess "Couldn't retrieve guideRNA_prep, $id, from database.\n";
    }
    return $guideRNA_prep;
}

=method fetch_by_ids

  Usage       : $guideRNA_preps = $guideRNA_prep_adaptor->fetch_by_ids( \@guideRNA_prep_ids );
  Purpose     : Fetch a list of guideRNA_preps given a list of db ids
  Returns     : Arrayref of Crispr::DB::GuideRNAPrep objects
  Parameters  : Arrayref of crispr-db guideRNA_prep ids
  Throws      : If no rows are returned from the database for one of ids
  Comments    : None

=cut

sub fetch_by_ids {
    my ( $self, $ids ) = @_;
	my @guideRNA_preps;
    foreach my $id ( @{$ids} ){
        push @guideRNA_preps, $self->fetch_by_id( $id );
    }
	
    return \@guideRNA_preps;
}

#=method fetch_by_type
#
#  Usage       : $guideRNA_preps = $guideRNA_prep_adaptor->fetch_by_type( $guideRNA_prep );
#  Purpose     : Fetch a guideRNA_prep object by type
#  Returns     : Crispr::DB::GuideRNAPrep object
#  Parameters  : type => Str
#  Throws      : If no rows are returned from the database
#  Comments    : None
#
#=cut
#
#sub fetch_by_type {
#    my ( $self, $type ) = @_;
#
#    my $guideRNA_prep = $self->_fetch( 'guideRNA_type = ?', [ $type, ] )->[0];
#    
#    if( !$guideRNA_prep ){
#        confess "Couldn't retrieve guideRNA_prep from database.\n";
#    }
#    return $guideRNA_prep;
#}

=method fetch_all_by_crRNA_id

  Usage       : $guideRNA_preps = $guideRNA_prep_adaptor->fetch_all_by_crRNA_id( 1 );
  Purpose     : Fetch a guideRNA_prep object by crRNA_id
  Returns     : Crispr::DB::GuideRNAPrep object
  Parameters  : plasmid name => Str
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_crRNA_id {
    my ( $self, $crRNA_id ) = @_;
    
    my $statement = "gp.crRNA_id = ?;";
    my $guideRNA_preps = $self->_fetch( $statement, [ $crRNA_id, ], );
    my @guideRNA_preps = sort { $a->db_id <=> $b->db_id } @{$guideRNA_preps};
    return \@guideRNA_preps;
}

=method fetch_all_by_injection_pool

  Usage       : $guideRNA_preps = $guideRNA_prep_adaptor->fetch_all_by_injection_pool( $inj_pool );
  Purpose     : Fetch a guideRNA_prep object by InjectionPool object
  Returns     : Crispr::DB::GuideRNAPrep object
  Parameters  : plasmid name => Str
  Throws      : If no rows are returned from the database or if too many rows are returned
  Comments    : None

=cut

sub fetch_all_by_injection_pool {
    my ( $self, $inj_pool ) = @_;
    
    # check object is an InjectionPool object
    if( !ref $inj_pool || !$inj_pool->isa('Crispr::DB::InjectionPool') ){
        confess "The supplied object should be a Crispr::DB::InjectionPool object, not a ",
            ref $inj_pool || 'String';
    }
    # sql statement
    my $sql = <<'END_SQL';
        SELECT
			gp.guideRNA_prep_id, gp.guideRNA_type, gp.concentration,
            gp.made_by, gp.date,
            ip.guideRNA_concentration,
            gp.plate_id, gp.well_id,
            cr.crRNA_id, crRNA_name, chr, start, end, strand,
            sequence, num_five_prime_Gs, score, coding_score, off_target_score,
            target_id, status_id, status_changed
        FROM guideRNA_prep gp, crRNA cr, injection i, injection_pool ip
        WHERE gp.crRNA_id = cr.crRNA_id AND
        gp.guideRNA_prep_id = ip.guideRNA_prep_id AND
        i.injection_id = ip.injection_id
END_SQL
    
    # check that either db_id or injection_name is defined
    my $params;
    if( defined $inj_pool->db_id ){
        $sql .= "AND ip.injection_id = ?;";
        $params = [ $inj_pool->db_id ];
    }
    elsif( defined $inj_pool->pool_name ){
        $sql .= "AND i.injection_name = ?;";
        $params = [ $inj_pool->pool_name ];
    }
    
    my $results;
    my $guideRNA_preps;
    eval{
        $results = $self->fetch_rows_for_generic_select_statement( $sql, $params, );
    };
    if( $EVAL_ERROR ){
        if( $EVAL_ERROR eq 'NO ROWS' ){
            warn "Couldn't find any guide RNA preps for the supplied injection pool, ",
                $params->[0], "\n";
        }
        else{
            confess $EVAL_ERROR, "\n";
        }   
    }
    else{
        foreach my $row ( @{$results} ){
            my %args = (
                guide_rna_prep => {
                    db_id => $row->[0],
                    guideRNA_type => $row->[1],
                    stock_concentration => $row->[2],
                    made_by => $row->[3],
                    date => $row->[4],
                    injection_concentration => $row->[5],
                },
                crRNA => {
                    crRNA_id => $row->[8],
                    name => $row->[9],
                    chr => $row->[10],
                    start => $row->[11],
                    end => $row->[12],
                    strand => $row->[13],
                    sequence => $row->[14],
                    five_prime_Gs => $row->[15],
                    status_id => $row->[20],
                    status_changed => $row->[21],
                },
                plate => {
                    plate_id => $row->[6],
                    well_id => $row->[7],
                },
            );
            push @{$guideRNA_preps}, $self->_make_new_guideRNA_prep_from_db( \%args );
        }
    }
    
    return $guideRNA_preps;
}
 
#_fetch
#
#Usage       : $guideRNA_prep = $self->_fetch( $where_clause, $where_parameters );
#Purpose     : Fetch GuideRNAPrep objects from the database with arbitrary parameteres
#Returns     : ArrayRef of Crispr::DB::GuideRNAPrep objects
#Parameters  : where_clause => Str (SQL where conditions)
#               where_parameters => ArrayRef of parameters to bind to sql statement
#Throws      : 
#Comments    :

my %guideRNA_prep_cache;
sub _fetch {
    my ( $self, $where_clause, $where_parameters ) = @_;
    my $dbh = $self->connection->dbh();
    
    my $sql = <<'END_SQL';
        SELECT
			guideRNA_prep_id,
            guideRNA_type,
            concentration,
            made_by,
            date,
            gp.plate_id,
            gp.well_id,
            cr.crRNA_id, crRNA_name, chr, start, end, strand,
            sequence, num_five_prime_Gs, score, off_target_score, coding_score,
            target_id, status_id, status_changed
        FROM guideRNA_prep gp, crRNA cr
        WHERE gp.crRNA_id = cr.crRNA_id
END_SQL

    if ($where_clause) {
        $sql .= 'AND ' . $where_clause;
    }

    my $sth = $self->_prepare_sql( $sql, $where_clause, $where_parameters, );
    $sth->execute();

    my ( $guideRNA_prep_id, $guideRNA_type, $stock_concentration,
        $made_by, $date, $plate_id, $well_id, $crRNA_id,
        $crRNA_name, $chr, $start, $end, $strand,
        $sequence, $num_five_prime_Gs, $score, $off_target_score, $coding_score,
        $target_id, $status_id, $status_changed, );
    
    $sth->bind_columns( \( $guideRNA_prep_id, $guideRNA_type, $stock_concentration,
        $made_by, $date, $plate_id, $well_id, $crRNA_id,
        $crRNA_name, $chr, $start, $end, $strand,
        $sequence, $num_five_prime_Gs, $score, $off_target_score, $coding_score,
        $target_id, $status_id, $status_changed, ) );

    my @guideRNA_preps = ();
    while ( $sth->fetch ) {
        my $guideRNA_prep;
        if( !exists $guideRNA_prep_cache{ $guideRNA_prep_id } ){
            my $crRNA = $self->crRNA_adaptor->_make_new_crRNA_from_db(
                [ $crRNA_id, $crRNA_name, $chr, $start, $end, $strand,
                $sequence, $num_five_prime_Gs, $score, $off_target_score, $coding_score,
                $target_id, undef, undef, $status_id, $status_changed, ]
            );
            
            my $well;
            if( $well_id && $plate_id ){
                my $plate = $self->plate_adaptor->fetch_empty_plate_by_id( $plate_id, );
                $well = Labware::Well->new(
                    position => $well_id,
                    plate => $plate,
                );
            }
            
            $guideRNA_prep = Crispr::DB::GuideRNAPrep->new(
                db_id => $guideRNA_prep_id,
                crRNA => $crRNA,
                guideRNA_type => $guideRNA_type,
                stock_concentration => $stock_concentration,
                made_by => $made_by,
                date => $date,
                well => $well,
            );
            $guideRNA_prep_cache{ $guideRNA_prep_id } = $guideRNA_prep;
        }
        else{
            $guideRNA_prep = $guideRNA_prep_cache{ $guideRNA_prep_id };
        }
        
        push @guideRNA_preps, $guideRNA_prep;
    }

    return \@guideRNA_preps;    
}

#_make_new_guideRNA_prep_from_db
#
#Usage       : $guideRNA_prep = $self->_make_new_guideRNA_prep_from_db( \@fields );
#Purpose     : Create a new Crispr::DB::GuideRNAPrep object from a db entry
#Returns     : Crispr::DB::GuideRNAPrep object
#Parameters  : HashRef of HashRefs
#Throws      : If input is not a HashRef
#Comments    : Expects a HashRef with keys crRNA, plate, guide_rna_prep
#               the values for these keys should be HashRefs of attributes

sub _make_new_guideRNA_prep_from_db {
    my ( $self, $info ) = @_;
    my $guideRNA_prep;
	
    my $guide_rna_info = $info->{guide_rna_prep};
    if( !exists $guideRNA_prep_cache{ $guide_rna_info->{db_id} } ){
        my ( $crRNA, $plate, $well, );
        my $crRNA_info = $info->{crRNA};
        if( defined $crRNA_info ){
            $crRNA = $self->crRNA_adaptor->_make_new_crRNA_from_db(
                [   $crRNA_info->{crRNA_id},
                    $crRNA_info->{name},
                    $crRNA_info->{chr},
                    $crRNA_info->{start},
                    $crRNA_info->{end},
                    $crRNA_info->{strand},
                    $crRNA_info->{sequence},
                    $crRNA_info->{five_prime_Gs},
                    undef, undef, undef, undef, undef, undef,
                    $crRNA_info->{status_id},
                    $crRNA_info->{status_changed},
                 ],
            );
        }
        my $plate_info = $info->{plate};
        if( defined $plate_info && defined $plate_info->{plate_id} ){
            $plate = $self->plate_adaptor->fetch_empty_plate_by_id( $plate_info->{plate_id} );
        }
        if( defined $plate_info->{well_id} && defined $plate ){
            $well = Labware::Well->new(
                position => $plate_info->{well_id},
                plate => $plate,
            );
        }
        
        $guideRNA_prep = Crispr::DB::GuideRNAPrep->new(
            db_id => $guide_rna_info->{db_id},
            crRNA => $crRNA,
            guideRNA_type => $guide_rna_info->{type},
            stock_concentration => $guide_rna_info->{stock_concentration},
            made_by => $guide_rna_info->{made_by},
            date => $guide_rna_info->{date},
            well => $well,
            injection_concentration => $guide_rna_info->{injection_concentration},
        );
        $guideRNA_prep_cache{ $guide_rna_info->{db_id} } =
            $guideRNA_prep;
    }
    else{
        $guideRNA_prep =
            $guideRNA_prep_cache{ $guide_rna_info->{db_id} };
    }
	
    return $guideRNA_prep;
}

=method delete_guideRNA_prep_from_db

  Usage       : $guide_rna_prep_adaptor->delete_guideRNA_prep_from_db( $guide_rna_prep );
  Purpose     : Delete a guide_rna_prep from the database
  Returns     : Crispr::DB::GuideRNAPrep object
  Parameters  : Crispr::DB::GuideRNAPrep object
  Throws      : 
  Comments    : Not inmplemented yet.

=cut

sub delete_guideRNA_prep_from_db {
	#my ( $self, $guideRNA_prep ) = @_;
	
	# first check guideRNA_prep exists in db
	
	# delete primers and primer pairs
	
	# delete transcripts
	
	# if guideRNA_prep has talen pairs, delete tale and talen pairs

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
 
    use Crispr::DB::DBConnection;
    my $db_connection = Crispr::DB::DBConnection->new(
        host => 'HOST',
        port => 'PORT',
        dbname => 'DATABASE',
        user => 'USER',
        pass => 'PASS',
    );
  
    my $guideRNA_prep_adaptor = $db_connection->get_adaptor( 'guideRNA_prep' );
    
    # store a guideRNA_prep object in the db
    $guideRNA_prep_adaptor->store( $guideRNA_prep );
    
    # retrieve a guideRNA_prep by id
    my $guideRNA_prep = $guideRNA_prep_adaptor->fetch_by_id( '214' );
  
    # retrieve a guideRNA_prep by combination of type and date
    my $guideRNA_prep = $guideRNA_prep_adaptor->fetch_by_type_and_date( 'guideRNA_prep_dnls_native', '2015-04-27' );
    

=head1 DESCRIPTION
 
 A GuideRNAPrepAdaptor is an object used for storing and retrieving GuideRNAPrep objects in an SQL database.
 The recommended way to use this module is through the DBAdaptor object as shown above.
 This allows a single open connection to the database which can be shared between multiple database adaptors.
 
=head1 DIAGNOSTICS
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
=head1 DEPENDENCIES
 
 
=head1 INCOMPATIBILITIES
 
