## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::EnzymeInfo;
## use critic

# ABSTRACT: EnzymeInfo object - holds information on restriction enzymes for the screening PCR product for a crRNA.

use namespace::autoclean;
use Moose;
use Moose::Util::TypeConstraints;
use lib '/software/team31/bioperl/bioperl-1-6-9/';
use Bio::Restriction::EnzymeCollection;
use Bio::Restriction::Analysis;
use Readonly;

=method crRNA

  Usage       : $enzyme_info->crRNA;
  Purpose     : Getter for the crRNA that this EnzymeInfo object is for.
  Returns     : Crispr::crRNA object
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'crRNA' => (
	is => 'ro',
	isa => 'Crispr::crRNA',
);

=method analysis

  Usage       : $enzyme_info->analysis;
  Purpose     : Getter for the restriction analysis for the crRNA target sequence
  Returns     : Bio::Restriction::Analysis object
  Parameters  : None
  Throws      : If input is given
  Comments    : The method call unique_cutters is delegated to this object
                so $enzyme_info->unique_cutters works just like
                    $enzyme_info->analysis->unique_cutters

=cut

has 'analysis' => (
	is => 'ro',
	isa => 'Bio::Restriction::Analysis',
    handles => {
        unique_cutters => 'unique_cutters',
    },
);

=method amplicon_analysis

  Usage       : $enzyme_info->amplicon_analysis;
  Purpose     : Getter for the restriction analysis for the whole screening PCR amplicon
  Returns     : Bio::Restriction::Analysis object
  Parameters  : None
  Throws      : If input is given
  Comments    : The method call unique_cutters_in_amplicon is delegated to this object
                so $enzyme_info->unique_cutters_in_amplicon works just like
                    $enzyme_info->amplicon_analysis->unique_cutters

=cut

has 'amplicon_analysis' => (
    is => 'ro',
    isa => 'Bio::Restriction::Analysis',
    handles => {
        unique_cutters_in_amplicon => 'unique_cutters',
    },
);

=method uniq_in_both

  Usage       : $enzyme_info->uniq_in_both;
  Purpose     : Getter for the enzymes that are unique in both the crRNA target
                sequence and the PCR amplicon
  Returns     : Bio::Restriction::EnzymeCollection object
  Parameters  : None
  Throws      : If input is given
  Comments    : None

=cut

has 'uniq_in_both' => (
    is => 'ro',
    isa => 'Bio::Restriction::EnzymeCollection',
    writer => '_set_enzymes',
);

my $_proximities_for;
my $_uniq_in_both_checked;

# This is to weaken the crRNA reference in the EnzymeInfo object.
# The crRNA object contains a reference to the EnzymeInfo object
# which would create a circular reference if we didn't do this.
around BUILDARGS => sub{
    my $method = shift;
    my $self = shift;
    my %args;
    
    if( !ref $_[0] ){
        for( my $i = 0; $i < scalar @_; $i += 2){
            my $k = $_[$i];
            my $v = $_[$i+1];
			if( $k eq 'crRNA' ){
                weaken( $v );
			}
            $args{ $k } = $v;
        }
        return $self->$method( \%args );
    }
    elsif( ref $_[0] eq 'HASH' ){
		if( exists $_[0]->{'crRNA'} ){
            weaken( $_[0]->{'crRNA'} );
		}
        return $self->$method( $_[0] );
    }
    else{
        confess "method new called without Hash or Hashref.\n";
    }
};

# check uniq_in_both for overlapping sites
around 'uniq_in_both' => sub {
    my ( $orig, $self, ) = @_;
    
    if( $_uniq_in_both_checked ){
        return $self->$orig;
    }
    else{
        my $enzymes = $self->_parse_uniq_in_both( $self->$orig );
        $self->_set_enzymes( $enzymes );
        $_uniq_in_both_checked = 1;
        return $enzymes;
    }
};

=method proximity_to_cut_site

  Usage       : $enzyme_info->proximity_to_cut_site( $enzyme );
  Purpose     : Calculates the proximity of the restriction enzyme recognition
                site to the crRNA cut-site.
  Returns     : Int (1000000 if enzyme cuts more than once)
  Parameters  : Bio::Restriction::Enzyme
  Throws      : If argument is not a Bio::Restriction::Enzyme object
  Comments    : Bio::Restriction::Analysis does not recognise overlapping
                restriction sites. If an enzyme is found to have more than one
                site, 1000000 is returned

=cut

sub proximity_to_cut_site {
    my ( $self, $enzyme, ) = @_;
    
    if( !defined $enzyme ){
        die "A Bio::Restriction::Enzyme object must be supplied!\n";
    }
    elsif( !ref $enzyme || !$enzyme->isa('Bio::Restriction::Enzyme') ){
        die join(q{ }, 'The supplied object must be a Bio::Restriction::Enzyme object, not',
                 ref $enzyme, ), "\n";
    }
    
    if( exists $_proximities_for->{ $enzyme->name } &&
        defined $_proximities_for->{ $enzyme->name } ){
        return $_proximities_for->{ $enzyme->name };
    }
    else{
        my $search_seq = $self->analysis->seq->seq;
        #warn $search_seq, "\n" if $debug;
        # make regex from $enzyme string
        my $f_regex = $self->_construct_enzyme_site_regex_from_target_seq( $enzyme->string );
        my $r_regex = $self->_construct_enzyme_site_regex_from_target_seq( $enzyme->revcom );
        my $found = 0;
        my ( $match_start, $match_end );
        while( $search_seq =~ m/$f_regex/g ){
            $found++;
            $match_start = pos($search_seq);
            $match_end = $match_start + length $enzyme->string;
        }
        if ( !$found ){
            while( $search_seq =~ m/$r_regex/g ){
                $found++;
                $match_start = pos($search_seq);
                $match_end = $match_start + length $enzyme->string;
            }
        }
        if ( $found == 0 ){
            die "Couldn't find enzyme cut-site\n",
                join("\t", $enzyme->name, $enzyme->site,
                     $search_seq, $f_regex, $r_regex, ), "\n";
        }
        elsif( $found > 1 ){
            # cutting does not take account of overlapping sites
            warn join("\t", $search_seq,
                join(q{ }, 'Enzyme', $enzyme->name, 'is supposed to be unique. Got',
                        $found, 'matches. Removing from analysis', ), ), "\n";
            return 1000000;
        }
        
        # Calculate distance from cut-site to restriction site
        # return 0 if cut-site fall within restriction site
        Readonly my $CUT_SITE => 17;
        my $distance = $CUT_SITE < $match_start    ?   $match_start - $CUT_SITE
            :       $CUT_SITE > $match_end      ?   $CUT_SITE - $match_end
            :                                       0;
        return $distance;
    }
}

################################################################################
# func _construct_enzyme_site_regex_from_target_seq
#
#  Usage       : $self->_construct_enzyme_site_regex_from_target_seq('GATATC');
#  Purpose     : Creates a Quoted Regular Expression from the supplied
#                enzyme recognition site.
#  Returns     : Regexp
#  Parameters  : String (Must be valid IUPAC codes)
#  Throws      : If any of the characters are not IUPAC codes for DNA bases
#  Comments    : None
################################################################################

sub _construct_enzyme_site_regex_from_target_seq {
	my ( $self, $target_str ) = @_;
	my %regex_for = (
		N => '[ACGT]',
		R => '[AG]',
		Y => '[CT]',
		S => '[CG]',
		W => '[AT]',
		M => '[AC]',
		K => '[GT]',
		B => '[CGT]',
		D => '[AGT]',
		H => '[ACT]',
		V => '[ACG]',
	);
	
	my $regex_str;
	foreach ( split //, uc $target_str ){
		if( exists $regex_for{$_} ){
			$regex_str .= $regex_for{$_};
		}
		elsif( m/[ACGT]/ ){
			$regex_str .= $_;
		}
		else{
			confess "Base, ", $_, " is not an accepted IUPAC code.\n";
		}
	}
	my $regex = qr/(?=($regex_str))/xms;
}

################################################################################
# func _parse_uniq_in_both
#
#  Usage       : $self->_parse_uniq_in_both( $enzyme_collection );
#  Purpose     : Goes through an enzyme collection and keeps only those that
#                do not have a proximity of 1000000
#  Returns     : Bio::Restriction:EnzymeCollection
#  Parameters  : Bio::Restriction:EnzymeCollection
#  Throws      : 
#  Comments    : None
################################################################################

sub _parse_uniq_in_both {
    my ( $self, $enzyme_collection ) = @_;
    
    my $new_enzymes = Bio::Restriction::EnzymeCollection->new( -empty => 1 );
    
    $new_enzymes->enzymes(
        grep { $self->proximity_to_cut_site( $_ ) != 1000000 } $enzyme_collection->each_enzyme() );
    
    return $new_enzymes;
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 NAME
 
<Crispr::EnzymeInfo> - <Module for Crispr::EnzymeInfo objects.>

 
=head1 SYNOPSIS
 
    use Crispr::EnzymeInfo;
    my $enzyme_info = Crispr::EnzymeInfo->new(
        crRNA => $crRNA,
        analysis => $ra,
        amplicon_analysis => $ra2,
        uniq_in_both => $enzymes
    );
    
    # get the proximity of a particular enzyme to the cut-site of the crRNA
    $enzyme_info->proximity_to_cut_site( $enzyme );
    
    # get the sequence of the pcr products
    $enzyme_info->amplicon_analysis->seq->seq
    
    # get the fragments for the unique cutters
    my $enzymes = $enzyme_info->amplicon_analysis->unique_cutters_in_amplicon
    foreach my $enzyme ( @{$enzymes} ){
        my @fragments = $enzyme_info->amplicon_analysis->fragments( $enzyme )
    }

=head1 DESCRIPTION
 
Object of this class hold the information on restriction enzymes and their cut-sites within both the crRNA target and a PCR amplicon. 
 
=head1 DIAGNOSTICS
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
=head1 DEPENDENCIES
 
 
=head1 INCOMPATIBILITIES
 

