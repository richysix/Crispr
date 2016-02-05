## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::CrisprPairAdaptor;
## use critic

# ABSTRACT: CrisprPairAdaptor - object for storing CrisprPair objects in and
# retrieving them from an SQL database.

use warnings;
use strict;
use namespace::autoclean;
use Moose;
use Crispr::Target;
use Crispr::crRNA;
use Crispr::DB::PlateAdaptor;
use Carp qw( cluck confess );
use DateTime;
use Readonly;

extends 'Crispr::DB::BaseAdaptor';

=method new

  Usage       : my $crispr_pair_adaptor = Crispr::DB::CrisprPairAdaptor->new(
					db_connection => $db_connection,
                );
  Purpose     : Constructor for creating CrisprPairAdaptor objects
  Returns     : Crispr::DB::CrisprPairAdaptor object
  Parameters  :     db_connection => $db_connection,
  Throws      : If parameters are not the correct type
  Comments    : It is not recommended to call Crispr::DB::CrisprPairAdaptor->new directly
                The recommended usage is to create a new Crispr::DB::DBConnection object
                and call get_adaptor( 'crRNA' );

=cut

=method store_crispr_pair

  Usage       : $crispr_pair_adaptor->store_crispr_pair( $crispr_pair );
  Purpose     : Stores the supplied crispr pair in the db associated with this
                Adaptor
  Returns     : 1 on Success
  Parameters  : Crispr::CrisprPair
  Throws      : If argument is not a CrisprPair
                If CrisprPair does not contain 2 crRNA objects
  Comments    : None

=cut

sub store_crispr_pair {
    my ( $self, $crispr_pair ) = @_;
    # make an Array of $crispr_pair and call store_crispr_pairs
    $self->store_crispr_pairs( [ $crispr_pair ] );
    return 1;
}

=method store

  Usage       : $crispr_pair_adaptor->store_crispr_pairs( $crispr_pair );
  Purpose     : Synonym for store_crispr_pair
  Returns     : 1 on Success
  Parameters  : Crispr::CrisprPair
  Throws      : If argument is not a CrisprPair
                If CrisprPair does not contain 2 crRNA objects
  Comments    : None

=cut

sub store {
    my ( $self, $crispr_pair ) = @_;
    # make an Array of $crispr_pair and call store_crispr_pairs
    $self->store_crispr_pairs( [ $crispr_pair ] );
    return 1;
}

=method store_crispr_pairs

  Usage       : $crispr_pair_adaptor->store_crispr_pairs( $crispr_pairs );
  Purpose     : Stores the supplied crispr pairs in the db associated with this
                Adaptor
  Returns     : 1 on Success
  Parameters  : ArrayRef of Crispr::CrisprPair
  Throws      : If any of the elements of the array are not CrisprPairs
                If any of the CrisprPairs does not contain 2 crRNA objects
  Comments    : None

=cut

sub store_crispr_pairs {
    my ( $self, $crispr_pairs, ) = @_;
    my $dbh = $self->connection->dbh();
    
    # check input
    if( !defined $crispr_pairs ){
        die "At least one Crispr Pair must be supplied!\n";
    }
    elsif( !ref $crispr_pairs || ref $crispr_pairs ne 'ARRAY' ){
        die "Crispr Pairs must be supplied as an ArrayRef!\n";
    }
    foreach( @{$crispr_pairs} ){
        if( !ref $_ || !$_->isa('Crispr::CrisprPair') ){
            die "Arguments must all be Crispr::CrisprPair objects.\n";
        }
    }
    
    foreach my $crispr_pair ( @{$crispr_pairs} ){
        if( !defined $crispr_pair->crRNA_1 || !defined $crispr_pair->crRNA_2 ){
            die "At least one of the crRNAs is not defined!\n";
        }
        # check whether the crRNAs already exist in the db
        my $check_statement = 'select count(*) from crRNA where chr = ? and start = ? and end = ? and strand = ? and target_id = ?;';
        my $get_db_ids_statement = 'select crRNA_id from crRNA where chr = ? and start = ? and end = ? and strand = ? and target_id = ?;';
        
        my $insert_st = 'insert into crRNA_pair values( ?, ?, ? );';
        
		$self->connection->txn( fixup => sub {
            # check whether the crRNAs already exist in the db and add if not
            foreach my $crRNA ( @{$crispr_pair->crRNAs} ){
                if( !$self->check_entry_exists_in_db( $check_statement,
                        [ $crRNA->chr, $crRNA->start, $crRNA->end, $crRNA->strand, $crRNA->target_id ] ) ){
                    # try and store it in the db
                    $self->crRNA_adaptor->store( $crRNA );
                }
                # check whether db ids are present in the crRNA objects
                elsif( !$crRNA->crRNA_id ){
                    # get them from the db
                    my $sth = $dbh->prepare( $get_db_ids_statement );
                    $sth->execute( $crRNA->chr, $crRNA->start, $crRNA->end, $crRNA->strand );
                    my $results;
                    while( my @fields = $sth->fetchrow_array ){
                        push @{$results}, \@fields;
                    }
                    if( scalar @{$results} == 0 ){
                        die "Could not find crRNA ", $crRNA->name, "in database!\n";
                    }
                    elsif( scalar @{$results} > 1 ){
                        die "Got too many results from the database for crRNA ", $crRNA->name, "!\n";
                    }
                    else{
                        $crRNA->crRNA_id( $results->[0]->[0] );
                    }
                }
			}
            
            # add info to crispr_pair table
			my $sth = $dbh->prepare($insert_st);
			$sth->execute( $crispr_pair->pair_id,
                $crispr_pair->crRNA_1->crRNA_id,
                $crispr_pair->crRNA_2->crRNA_id,
			);
			
			my $last_id;
			$last_id = $dbh->last_insert_id( 'information_schema', $self->dbname(), 'crRNA_pair', 'crRNA_pair_id' );
			$crispr_pair->_set_pair_id( $last_id );
			$sth->finish();
            
        } );
    }
}


__PACKAGE__->meta->make_immutable;
1;


__END__

=pod

=head1 SYNOPSIS
 
    use Crispr::DB::DBConnection;
    use Crispr::DB::CrisprPairAdaptor;
    
    # make a new db adaptor
    my $db_adaptor = Crispr::DB::DBConnection->new(
		host => 'HOST',
		port => 'PORT',
		dbname => 'DATABASE',
		user => 'USER',
		pass => 'PASS',
		connection => $dbc,
    );
    
    # get a crRNA adaptor using the get_adaptor method
    my $crispr_pair_adaptor = $db_adaptor->get_adaptor( 'crispr_pair' );
  
  
=head1 DESCRIPTION
 
    An object of this class represents a connector to a mysql database 
    for retrieving crispr pair objects from and storing them to the database.
 
 
=head1 SUBROUTINES/METHODS 
 
 
=head1 DIAGNOSTICS
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
 
=head1 DEPENDENCIES
 
 
=head1 INCOMPATIBILITIES
 
