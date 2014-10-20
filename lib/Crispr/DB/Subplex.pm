## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::DB::Subplex;
## use critic

# ABSTRACT: Subplex object - representing a subset of samples on a multiplexed sequencing run

use warnings;
use strict;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use DateTime;

with 'Crispr::SharedMethods';

=method new

  Usage       : my $inj = Crispr::DB::Subplex->new(
					db_id => undef,
                    plex => $plex,
					injection_pool => $injection_pool,
					plate_num => 1,
                );
  Purpose     : Constructor for creating Subplex objects
  Returns     : Crispr::DB::Subplex object
  Parameters  : db_id => Int,
                plex => Crispr::DB:Plex,
                injection_pool => Crispr::DB::InjectionPool,
                plate_num =>  1, 2, 3 OR 4
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method db_id

  Usage       : $inj->db_id;
  Purpose     : Getter/Setter for Subplex db_id attribute
  Returns     : Int (can be undef)
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'db_id' => (
    is => 'rw',
    isa => 'Maybe[Int]',
);

=method plex

  Usage       : $inj->plex;
  Purpose     : Getter for Subplex plex attribute
  Returns     : Str
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

has 'plex' => (
    is => 'ro',
    isa => 'Crispr::DB::Plex',
    handles => {
        plex_name => 'plex_name',
    },
);

=method injection_pool

  Usage       : $inj->injection_pool;
  Purpose     : Getter for injection_pool attribute
  Returns     : Crispr::DB::InjectionPool
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'injection_pool' => (
    is => 'ro',
    isa => 'Crispr::DB::InjectionPool',
);

=method plate_num

  Usage       : $inj->plate_num;
  Purpose     : Getter for plate_num attribute
  Returns     : DateTime
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'plate_num' => (
    is => 'ro',
    isa => enum( [ qw{ 1 2 3 4 } ] ),
);

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 SYNOPSIS
 
    use Crispr::DB::Subplex;
    my $inj = Crispr::DB::Subplex->new(
        db_id => undef,
        plex => $inj,
        injection_pool => $injection_pool,
        plate_num => 1,
    );    
    
=head1 DESCRIPTION
 
Objects of this class represent a sample for screening by sequencing.

=head1 DIAGNOSTICS


=head1 DEPENDENCIES
 
 Moose
 
=head1 INCOMPATIBILITIES
 

