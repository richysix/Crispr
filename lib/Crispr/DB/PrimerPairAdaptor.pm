## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::PrimerPairAdaptor;
## use critic

# ABSTRACT: PrimerPairAdaptor object - object for storing PrimerPair objects in and retrieving them from a SQL database

use namespace::autoclean;
use Moose;
use English qw( -no_match_vars );
use DateTime;
use Readonly;
use Crispr::Primer;
use Crispr::PrimerPair;

extends 'Crispr::DB::BaseAdaptor';

=method new

  Usage       : my $primer_adaptor = Crispr::DB::PrimerPairAdaptor->new(
					db_connection => $db_connection,
                );
  Purpose     : Constructor for creating primer adaptor objects
  Returns     : Crispr::DB::PrimerPairAdaptor object
  Parameters  :     db_connection => Crispr::DB::DBConnection object,
  Throws      : If parameters are not the correct type
  Comments    : The preferred method for constructing a PrimerAdaptor is to use the
                get_adaptor method with a previously constructed DBConnection object

=cut

=method plate_adaptor

  Usage       : $primer_adaptor->plate_adaptor;
  Purpose     : Getter for a plate_adaptor
  Returns     : Crispr::DB::PlateAdaptor
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'plate_adaptor' => (
    is => 'ro',
    isa => 'Crispr::DB::PlateAdaptor',
    lazy => 1,
    builder => '_build_plate_adaptor',
);

my $date_obj = DateTime->now();
Readonly my $PLATE_TYPE => '96';

=method store

  Usage       : $primer_pair_adaptor->store;
  Purpose     : method to store a primer_pair in the database.
  Returns     : 1 on Success.
  Parameters  : Crispr::PrimerPair
                Crispr::crRNA
  Throws      : If input is not correct type
  Comments    : 

=cut

sub store {
    # Primers must have already been added to the db
    my ( $self, $primer_pair, $crRNAs ) = @_;
    my $dbh = $self->connection->dbh();
    
    if( !$primer_pair ){
        confess "primer_pair must be supplied in order to add oligos to the database!\n";
    }
    if( !ref $primer_pair || !$primer_pair->isa('Crispr::PrimerPair') ){
        confess "Supplied object must be a Crispr::PrimerPair object, not ", ref $primer_pair, ".\n";
    }
    if( !$crRNAs ){
        confess "At least one crRNA_id must be supplied in order to add oligos to the database!\n";
    }
    elsif( ref $crRNAs ne 'ARRAY' ){
        confess "crRNA_ids must be supplied as an ArrayRef!\n";
    }
    foreach ( @{$crRNAs} ){
        if( !ref $_ || !$_->isa('Crispr::crRNA') ){
            confess "Supplied object must be a Crispr::crRNA object, not ", ref $_, ".\n";
        }
    }
    # statement to check primers exist in db
    my $check_primer_st = "select count(*) from primer where primer_id = ?;";
    # statement to add pair into primer_pair table
    my $pair_statement = "insert into primer_pair values( ?, ?, ?, ?, ?, ?, ?, ?, ? );";
    my $pair_to_crRNA_statement = "insert into amplicon_to_crRNA values( ?, ? );";
    
    $self->connection->txn(  fixup => sub {
        # check whether primers already exist in database
        foreach my $primer ( $primer_pair->left_primer, $primer_pair->right_primer ){
            if( !$self->check_entry_exists_in_db( $check_primer_st, [ $primer->primer_id ] ) ){
                confess "Couldn't locate primer, ", $primer_pair->left_primer->primer_name, "in the database!\n",
                "Primers must be added to database before primer pair info.\n";
            }
        }
        
        # add primer pair info
        my $sth = $dbh->prepare($pair_statement);
        $sth->execute(
            undef,
            $primer_pair->type,
            $primer_pair->left_primer->primer_id,
            $primer_pair->right_primer->primer_id,
            $primer_pair->seq_region,
            $primer_pair->seq_region_start,
            $primer_pair->seq_region_end,
            $primer_pair->seq_region_strand,
            $primer_pair->product_size,
        );
        my $last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'primer_pair', 'primer_pair_id' );
        $primer_pair->primer_pair_id( $last_id );
        
        $sth = $dbh->prepare($pair_to_crRNA_statement);
        foreach my $crRNA ( @{$crRNAs} ){
            $sth->execute(
                $last_id,
                $crRNA->crRNA_id,
            );
        }
        $sth->finish();
    } );
    return 1;
}

sub fetch_primer_pair_by_crRNA {
    my ( $self, $crRNA, ) = @_;
    
    my $results = $self->fetch_rows_expecting_single_row;
}

sub _make_new_primer_pair_from_db {
    my ( $self, $fields, ) = @_;
    
    my $l_p_seq = defined $fields->[6] ? $fields->[6] . $fields->[1] : $fields->[1];
    my $left_primer = Crispr::Primer->new(
        primer_id => $fields->[0],
        sequence => $l_p_seq,
        seq_region => $fields->[2],
        seq_region_start => $fields->[3],
        seq_region_end => $fields->[4],
        seq_region_strand => $fields->[5],
        plate_id => $fields->[7],
        well => $fields->[8],
    );
    
    my $r_p_seq = defined $fields->[15] ? $fields->[15] . $fields->[10] : $fields->[10];
    my $right_primer = Crispr::Primer->new(
        primer_id => $fields->[9],
        sequence => $r_p_seq,
        seq_region => $fields->[11],
        seq_region_start => $fields->[12],
        seq_region_end => $fields->[13],
        seq_region_strand => $fields->[14],
        plate_id => $fields->[16],
        well => $fields->[17],
    );
    
    my $pair_name;
    if( defined $fields->[22] ){
        $pair_name .= $fields->[22] . ":";
    }
    $pair_name .= join("-", $fields->[23], $fields->[24], );
    if( defined $fields->[25] ){
        $pair_name .= ":" . $fields->[25];
    }
    my $primer_pair = Crispr::PrimerPair->new(
        primer_pair_id => $fields->[18],
        pair_name => $pair_name,
        type => $fields->[19],
        product_size => $fields->[26],
        left_primer => $left_primer,
        right_primer => $right_primer,
    );
    
    return $primer_pair;
}

#_build_plate_adaptor

  #Usage       : $crRNAs = $crRNA_adaptor->_build_plate_adaptor();
  #Purpose     : Internal method to create a new Crispr::DB::PlateAdaptor
  #Returns     : Crispr::DB::PlatePrepAdaptor
  #Parameters  : None
  #Throws      : 
  #Comments    : 

sub _build_plate_adaptor {
    my ( $self, ) = @_;
    return $self->db_connection->get_adaptor( 'plate' );
}


1;

