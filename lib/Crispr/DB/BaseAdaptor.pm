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

## ADAPTOR TYPES
=method target_adaptor

  Usage       : $self->target_adaptor();
  Purpose     : Getter for a target_adaptor.
  Returns     : Str
  Parameters  : None
  Throws      :
  Comments    :

=cut

has 'target_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::TargetAdaptor',
    lazy => 1,
    builder => '_build_target_adaptor',
);

=method crRNA_adaptor

  Usage       : $self->crRNA_adaptor();
  Purpose     : Getter for a crRNA_adaptor.
  Returns     : Crispr::DB::crRNAAdaptor
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'crRNA_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::crRNAAdaptor',
    lazy => 1,
    builder => '_build_crRNA_adaptor',
);

=method guideRNA_prep_adaptor

  Usage       : $self->guideRNA_prep_adaptor();
  Purpose     : Getter for a guideRNA_prep_adaptor.
  Returns     : Crispr::DB::GuideRNAPrepAdaptor
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'guideRNA_prep_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::GuideRNAPrepAdaptor',
    lazy => 1,
    builder => '_build_guideRNA_prep_adaptor',
);

=method plate_adaptor

  Usage       : $self->plate_adaptor();
  Purpose     : Getter for a plate_adaptor.
  Returns     : Str
  Parameters  : None
  Throws      :
  Comments    :

=cut

has 'plate_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::PlateAdaptor',
    lazy => 1,
    builder => '_build_plate_adaptor',
);

=method primer_pair_adaptor

  Usage       : $plate_adaptor->primer_pair_adaptor;
  Purpose     : Getter for a PrimerPairadaptor
  Returns     : Crispr::DB::PrimerPairAdaptor
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'primer_pair_adaptor' => (
	is => 'ro',
	isa => 'Crispr::DB::PrimerPairAdaptor',
	lazy => 1,
	builder => '_build_primer_pair_adaptor',
);

=method primer_adaptor

  Usage       : $primer_adaptor->primer_adaptor;
  Purpose     : Getter for a primer_adaptor
  Returns     : Crispr::DB::PlateAdaptor
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'primer_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::PrimerAdaptor',
    lazy => 1,
    builder => '_build_primer_adaptor',
);

=method cas9_adaptor

  Usage       : $self->cas9_adaptor();
  Purpose     : Getter for a cas9_adaptor.
  Returns     : Crispr::DB::Cas9Adaptor
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'cas9_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::Cas9Adaptor',
    lazy => 1,
    builder => '_build_cas9_adaptor',
);

=method cas9_prep_adaptor

  Usage       : $self->cas9_prep_adaptor();
  Purpose     : Getter for a cas9_prep_adaptor.
  Returns     : Crispr::DB::Cas9PrepAdaptor
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'cas9_prep_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::Cas9PrepAdaptor',
    lazy => 1,
    builder => '_build_cas9_prep_adaptor',
);

=method plex_adaptor

  Usage       : $self->plex_adaptor();
  Purpose     : Getter for a plex_adaptor.
  Returns     : Crispr::DB::PlexAdaptor
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'plex_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::PlexAdaptor',
    lazy => 1,
    builder => '_build_plex_adaptor',
);

=method sample_adaptor

  Usage       : $self->sample_adaptor();
  Purpose     : Getter for a sample_adaptor.
  Returns     : Crispr::DB::SampleAdaptor
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'sample_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::SampleAdaptor',
    lazy => 1,
    builder => '_build_sample_adaptor',
);

=method sample_amplicon_adaptor

  Usage       : $self->sample_amplicon_adaptor();
  Purpose     : Getter for a sample_amplicon_adaptor.
  Returns     : Crispr::DB::SampleAdaptor
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'sample_amplicon_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::SampleAmpliconAdaptor',
    lazy => 1,
    builder => '_build_sample_amplicon_adaptor',
);

=method analysis_adaptor

  Usage       : $self->analysis_adaptor();
  Purpose     : Getter for a analysis_adaptor.
  Returns     : Crispr::DB::AnalysisAdaptor
  Parameters  : None
  Throws      :
  Comments    :

=cut

has 'analysis_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::AnalysisAdaptor',
    lazy => 1,
    builder => '_build_analysis_adaptor',
);

=method injection_pool_adaptor

  Usage       : $self->injection_pool_adaptor();
  Purpose     : Getter for a injection_pool_adaptor.
  Returns     : Crispr::DB::InjectionPoolAdaptor
  Parameters  : None
  Throws      :
  Comments    :

=cut

has 'injection_pool_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::InjectionPoolAdaptor',
    lazy => 1,
    builder => '_build_injection_pool_adaptor',
);

=method allele_adaptor

  Usage       : $self->allele_adaptor();
  Purpose     : Getter for a allele_adaptor.
  Returns     : Crispr::DB::AlleleAdaptor
  Parameters  : None
  Throws      :
  Comments    :

=cut

has 'allele_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::AlleleAdaptor',
    lazy => 1,
    builder => '_build_allele_adaptor',
);

my $statuses = {
	REQUESTED => 1,
	DESIGNED => 2,
	ORDERED => 3,
	MADE => 4,
	INJECTED => 5,
	MISEQ_EMBRYO_SCREENING => 6,
	FAILED_EMBRYO_SCREENING => 7,
	PASSED_EMBRYO_SCREENING => 8,
	SPERM_FROZEN => 9,
	MISEQ_SPERM_SCREENING => 10,
	FAILED_SPERM_SCREENING => 11,
	PASSED_SPERM_SCREENING => 12,
	SHIPPED => 13,
	SHIPPED_AND_IN_SYSTEM => 13,
	IN_SYSTEM => 13,
	CARRIERS => 14,
	F1_FROZEN => 15, 
};

=method get_status_position

  Usage       : $self->get_status_position( $check_statement, $params );
  Purpose     : returns the position of a supplied status in the hierarchy of statuses
  Returns     : Int (undef if status doesn't exist)
  Parameters  : Str (status)
  Throws      :
  Comments    :

=cut

sub get_status_position {
    my ( $self, $status ) = @_;
    if( exists $statuses->{$status} ){
        return $statuses->{$status};
    }
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
            confess 'NO ROWS';
        }
        else{
            confess "An unexpected problem occurred. $EVAL_ERROR\n";
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

#_fetch_status_from_id
#
#Usage       : $status = $self->_fetch_status_from_id( $status_id );
#Purpose     : Fetch a status from the status table using a status id
#Returns     : Str => status_id
#Parameters  : 
#Throws      :
#Comments    :

sub _fetch_status_from_id {
    my ( $self, $status_id ) = @_;
    my $statement = 'SELECT status FROM status WHERE status_id = ?';
    my $params = [ $status_id ];
    my $status = $self->fetch_rows_expecting_single_row( $statement, $params, );
    return $status->[0];
}

#_fetch_status_id_from_status
#
#Usage       : $targets = $self->_fetch_status_id_from_status( $status );
#Purpose     : Fetch a status_id from the status table using a status
#Returns     : Int => status_id
#Parameters  : Str => status
#Throws      :
#Comments    :

sub _fetch_status_id_from_status {
    my ( $self, $status ) = @_;
    my $statement = 'SELECT status_id FROM status WHERE status = ?';
    my $params = [ $status ];
    my $status_id = $self->fetch_rows_expecting_single_row( $statement, $params, );
    return $status_id->[0];
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
    'Crispr::DB::BaseAdaptor' => {
        'NO ROWS'   => "object does not exist in the database.",
        'ERROR'     => "BaseAdaptor ERROR",
    },
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

    my $class = ref $self;
    if( exists $reports_for{ $class } ){
        my ( $error, $message );
        if( $error_msg =~ m/\A([A-Z[:space:]]+)\sat/xms ){
            $error = $1;
            if( $reports_for{ $class }->{$error} ){
                $message = $reports_for{ $class }->{$error};
            }
            else{
                $message = $error_msg;
            }
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
        die join("\n", $class,
                        $statement,
                        'Params: ', join(",", @{$params} ),
            ), "\n";
    }
}

#_build_allele_adaptor

  #Usage       : $allele_adaptor = $self->_build_allele_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::InjectionPoolAdaptor
  #Returns     : Crispr::DB::InjectionPoolAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_allele_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'allele' );
}

#_build_analysis_adaptor

  #Usage       : $analysis_adaptor = $self->_build_analysis_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::AnalysisAdaptor
  #Returns     : Crispr::DB::AnalysisAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_analysis_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'analysis' );
}

#_build_cas9_adaptor

  #Usage       : $crRNAs = $crRNA_adaptor->_build_cas9_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::Cas9Adaptor
  #Returns     : Crispr::DB::Cas9PrepAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_cas9_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'cas9' );
}

#_build_cas9_prep_adaptor

  #Usage       : $cas9_prep_adaptor = $self->_build_cas9_prep_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::Cas9PrepAdaptor
  #Returns     : Crispr::DB::Cas9PrepAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_cas9_prep_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'cas9_prep' );
}

#_build_crispr_pair_adaptor

  #Usage       : $crispr_pair_adaptor = $self->_build_crispr_pair_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::CrisprPairAdaptor
  #Returns     : Crispr::DB::CrisprPairAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_crispr_pair_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'crispr_pair' );
}

#_build_crRNA_adaptor

  #Usage       : $crRNA_adaptor = $self->_build_crRNA_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::crRNAAdaptor
  #Returns     : Crispr::DB::crRNAAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_crRNA_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'crRNA' );
}

#_build_guideRNA_prep_adaptor

  #Usage       : $guideRNA_prep_adaptor = $self->_build_guideRNA_prep_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::GuideRNAPrepAdaptor
  #Returns     : Crispr::DB::GuideRNAPrepAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_guideRNA_prep_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'guideRNA_prep' );
}

#_build_injection_pool_adaptor

  #Usage       : $injection_pool_adaptor = $self->_build_injection_pool_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::InjectionPoolAdaptor
  #Returns     : Crispr::DB::InjectionPoolAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_injection_pool_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'injection_pool' );
}

#_build_plate_adaptor

  #Usage       : $crRNAs = $crRNA_adaptor->_build_plate_adaptor( $well, $type );
  #Purpose     : Internal method to create a new Crispr::DB::PlateAdaptor
  #Returns     : Crispr::DB::PlateAdaptor
  #Parameters  : None
  #Throws      :
  #Comments    :

sub _build_plate_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'plate' );
}

#_build_plex_adaptor

  #Usage       : $plex_adaptor = $self->_build_plex_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::PlexAdaptor
  #Returns     : Crispr::DB::PlexAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_plex_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'plex' );
}

#_build_primer_adaptor

  #Usage       : $crRNAs = $crRNA_adaptor->_build_primer_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::PlateAdaptor
  #Returns     : Crispr::DB::PlatePrepAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_primer_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'primer' );
}

=method _build_primer_pair_adaptor

  Usage       : $primer_pair_adaptor->_build_primer_pair_adaptor;
  Purpose     : Stores a plate in the db
  Returns     : Crispr::Plate
  Parameters  : Crispr::Plate
  Throws      : If plate is not supplied
                If supplied parameter is not a Crispr::Plate object
  Comments    : 

=cut

sub _build_primer_pair_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'primer_pair' );
}

#_build_sample_adaptor

  #Usage       : $sample_adaptor = $self->_build_sample_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::InjectionPoolAdaptor
  #Returns     : Crispr::DB::InjectionPoolAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_sample_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'sample' );
}

#_build_sample_amplicon_adaptor

  #Usage       : $sample_amplicon_adaptor = $self->_build_sample_amplicon_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::InjectionPoolAdaptor
  #Returns     : Crispr::DB::InjectionPoolAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_sample_amplicon_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'sample_amplicon' );
}


#_build_target_adaptor

  #Usage       : $crRNAs = $crRNA_adaptor->_build_target_adaptor( $well, $type );
  #Purpose     : Internal method to create a new Crispr::DB::TargetAdaptor
  #Returns     : Crispr::DB::TargetAdaptor
  #Parameters  : None
  #Throws      :
  #Comments    :

sub _build_target_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'target' );
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 DESCRIPTION

This is the parent class for all database adaptors.
It has an attribute for the already open database connection (Crispr::DB::DBConnection).
It also provides a set of common database methods that can be used by all adaptor objects.
