## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::crRNA;
## use critic

# ABSTRACT: crRNA object - representing a synthetic guide_RNA

use warnings;
use strict;
use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use Crispr::OffTarget;
use Crispr::EnzymeInfo;
use Bio::Seq;
use Bio::Restriction::EnzymeCollection;
use Bio::Restriction::Analysis;
use Carp;

use Number::Format;
my $num = new Number::Format( DECIMAL_DIGITS => 3, );

enum 'Crispr::crRNA::Strand', [qw( 1 -1 )];

subtype 'Crispr::crRNA::DNA',
    as 'Str',
    where { my $ok = 1;
            $ok = 0 if $_ eq '';
            my @bases = split //, $_;
            foreach my $base ( @bases ){
                if( $base !~ m/[ACGT]/ ){
                    $ok = 0;
                }
            }
            return $ok;
    },
    message { "Not a valid DNA sequence.\n" };

=method new

  Usage       : my $crispr = Crispr::crRNA->new(
					crRNA_id => undef,
					target => $target,
					chr => '5',
					start => 20103030,
					end => 20103930,
					strand => '1',
					sequence => 'GAGATAGACATAGACAGTCGG',
					species => 'zebrafish',
					five_prime_Gs => 2,
					off_target_hits => $off_target_hits,
					coding_scores => $HashRef,
					unique_restriction_sites => $enzyme_collection,
					plasmid_backbone => 'pDR274',
					primer_pairs => $primer_pairs,
					crRNA_adaptor => $crRNA_adaptor,
                );
  Purpose     : Constructor for creating crRNA objects
  Returns     : Crispr::crRNA object
  Parameters  : crRNA_id => Int,
				target => Crispr::Target,
				chr => String,
				start => Int,
				end => Int,
				strand => '1', '-1', '+' OR '-',
				sequence => String,
				species => String,
				five_prime_Gs => Int,
				off_target_hits => Crispr::OffTarget,
				coding_scores => HashRef,
				unique_restriction_sites => Crispr::EnzymeInfo,
				plasmid_backbone => String,
				primer_pairs => ArrayRef of Crispr::PrimerPair,
				crRNA_adaptor => Crispr::Adaptors::crRNAAdaptor,
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method crRNA_id

  Usage       : $crRNA->crRNA_id;
  Purpose     : Getter for crRNA_id (database id) attribute
  Returns     : Int (can be undef)
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'crRNA_id' => (
    is => 'rw',
    isa => 'Maybe[Int]',
);

=method target

  Usage       : $crRNA->target;
  Purpose     : Getter for associated target
  Returns     : Crispr::Target object
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'target' => (
    is => 'rw',
    isa => 'Crispr::Target',
    handles => {
        target_id => 'target_id',
        target_name => 'name',
		target_summary => 'summary',
        target_info => 'info',
        assembly => 'assembly',
        target_gene_name => 'gene_name',
        target_gene_id => 'gene_id',
    },
);

=method chr

  Usage       : $crRNA->chr;
  Purpose     : Getter for chr attribute
  Returns     : String (can be undef)
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'chr' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

=method start

  Usage       : $crRNA->start;
  Purpose     : Getter for start attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

=method end

  Usage       : $crRNA->end;
  Purpose     : Getter for end attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has [ 'start', 'end' ] => (
    is => 'ro',
    isa => 'Int',
);

=method strand

  Usage       : $crRNA->strand;
  Purpose     : Getter for strand attribute
  Returns     : '1', '-1', '+' or '-'
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'strand' => (
    is => 'ro',
    isa => 'Crispr::crRNA::Strand',
    default => '1',
);

=method sequence

  Usage       : $crRNA->sequence;
  Purpose     : Getter for sequence attribute
  Returns     : String (Must be a DNA sequence - ACGT only)
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'sequence' => (
    is => 'ro',
    isa => 'Crispr::crRNA::DNA',
);

=method species

  Usage       : $crRNA->species;
  Purpose     : Getter for species attribute
  Returns     : String (can be undef)
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'species' => (
    is => 'ro',
    isa => 'Maybe[Str]',
    lazy => 1,
    builder => '_build_species',
);

=method five_prime_Gs

  Usage       : $crRNA->five_prime_Gs;
  Purpose     : Getter for five_prime_Gs attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'five_prime_Gs' => (
	is => 'rw',
	isa => enum( [ qw{ 0 1 2 } ] ),
	lazy => 1,
	builder => '_build_five_prime_Gs',
);

=method off_target_hits

  Usage       : $crRNA->off_target_hits;
  Purpose     : Getter for off_target_hits attribute
  Returns     : Crispr::OffTarget object
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'off_target_hits' => (
    is => 'rw',
    isa => 'Maybe[Crispr::OffTarget]',
    handles => {
        off_target_info => 'info',
        off_target_score => 'score',
        seed_score => 'seed_score',
        seed_hits => 'seed_hits',
        exonerate_score => 'exonerate_score',
        exonerate_hits => 'exonerate_hits',
    },
);

=method coding_scores

  Usage       : $crRNA->coding_scores;
  Purpose     : Getter for coding_scores attribute
  Returns     : HashRef
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'coding_scores' => (
    is => 'ro',
    isa => 'HashRef',
	writer => '_set_coding_scores',
);

=method unique_restriction_sites

  Usage       : $crRNA->unique_restriction_sites;
  Purpose     : Getter for unique_restriction_sites attribute
  Returns     : Crispr::EnzymeInfo object
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'unique_restriction_sites' =>(
    is => 'rw',
    isa => 'Maybe[Crispr::EnzymeInfo]',
);

=method plasmid_backbone

  Usage       : $crRNA->plasmid_backbone;
  Purpose     : Getter for plasmid_backbone attribute
  Returns     : 'pDR274', 'pGERETY-1260' or 'pGERETY-1261'
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'plasmid_backbone' => (
	is => 'ro',
	isa => enum( [ qw{ pDR274 pGERETY-1260 pGERETY-1261 } ] ),
	lazy => 1,
	builder => '_build_backbone',
);

=method primer_pairs

  Usage       : $crRNA->primer_pairs;
  Purpose     : Getter for primer_pairs attribute
  Returns     : ArrayRef of Crispr::PrimerPair objects
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'primer_pairs' => (
	is => 'rw',
	isa => 'Maybe[ArrayRef[Crispr::PrimerPair]]',
);

=method crRNA_adaptor

  Usage       : $crRNA->crRNA_adaptor;
  Purpose     : Getter for crRNA_adaptor attribute
  Returns     : Crispr::Adaptors::crRNAAdaptor object
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'crRNA_adaptor' => (
    is => 'rw',
    isa => 'Crispr::Adaptors::crRNAAdaptor',
);

around BUILDARGS => sub{
    my $method = shift;
    my $self = shift;
    my %args;
	
    if( !ref $_[0] ){
		for( my $i = 0; $i < scalar @_; $i += 2 ){
			my $k = $_[$i];
			my $v = $_[$i+1];
			if( $k eq 'species' ){
				my $species = $self->_parse_species( $v );
				$v = $species;
			}
			elsif( $k eq 'chr' && ( defined $v && $v eq '' ) ){
				$v = undef;
			}
			elsif( $k eq 'strand' && ( $v ne '1' && $v ne '-1' ) ){
				my $strand = $self->_parse_strand_input( $v );
				$v = $strand;
			}
			$args{ $k } = $v;
		}
	    return $self->$method( \%args );
	}
    elsif( ref $_[0] eq 'HASH' ){
        if( exists $_[0]->{'species'} ){
            if( defined $_[0]->{'species'} ){
				my $species = $self->_parse_species( $_[0]->{'species'} );
                $_[0]->{'species'} = $species;
            }
        }
        elsif( exists $_[0]->{'chr'} && ( defined $_[0]->{'chr'} && $_[0]->{'chr'} eq '' ) ){
            $_[0]->{'chr'} = undef;
        }
        elsif( exists $_[0]->{'strand'} && ( $_[0]->{'strand'} ne '1' && $_[0]->{'strand'} ne '-1' ) ){
			my $strand = $self->_parse_strand_input( $_[0]->{'strand'} );
			$_[0]->{'strand'} = $strand;
        }
        return $self->$method( $_[0] );
    }
    else{
        confess "method new called without Hash or Hashref.\n";
    }	
};

#_parse_strand_input
#
#Usage       : $crRNA->_parse_strand_input( '+' );
#Purpose     : accepts '+' or '-' and converts to '1' or '-1'
#				retruns undef for anything else
#Returns     : '1' OR '-1'
#Parameters  : String
#Throws      : 
#Comments    :

sub _parse_strand_input {
	my ( $self, $strand ) = @_;
	if( $strand eq '+' ){
		return '1';
	}
	elsif( $strand eq '-' ){
		return '-1';
	}
	else{
		return undef;
	}
}

#_parse_species
#
#Usage       : $crRNA->_parse_species( 'Danio_rerio' );
#Purpose     : tries to force common names for species
#Returns     : String
#Parameters  : String
#Throws      : 
#Comments    :

sub _parse_species {
	# force common names for species
	my ( $self, $input, ) = @_;
    my $species;
    my %common_names_for = (
        zebrafish => 'zebrafish',
        'Danio rerio' => 'zebrafish',
        'Danio_rerio' => 'zebrafish',
        'danio_rerio' => 'zebrafish',
        mouse => 'mouse',
        'Mus musculus' => 'mouse',
        'Mus_musculus' => 'mouse',
        'mus_musculus' => 'mouse',
        human => 'human',
        'Homo sapiens' => 'human',
        'Homo_sapiens' => 'human',
        'homo_sapiens' => 'human',
    );
    
    if( !$input ){
        return undef;
    }
    else{
        if( exists $common_names_for{ $input } ){
            $species = $common_names_for{ $input };
            return $species;
        }
        else{
            return $input;
        }
    }
};

=method top_restriction_sites

  Usage       : $crRNA->top_restriction_sites;
  Purpose     : Retrieves the specified number of enzymes from unique_restriction_sites,
				sorted by length of site
  Returns     : String
  Parameters  : Int
  Throws      : 
  Comments    : 

=cut

sub top_restriction_sites {
    my ( $self, $num ) = @_;
    if( !$num ){
        $num = 2;
    }
    
    if( $self->unique_restriction_sites ){
        my @restriction_enzymes = map { join(':', $_->name, $_->site) }
                                    sort { length($b->string) <=> length($a->string) } $self->enzymes;
        if( scalar @restriction_enzymes > $num ){
            return join(',', @restriction_enzymes[0..$num-1] );
        }
        else{
            return join(',', @restriction_enzymes );
        }
    }
    else{
        return undef;
    }
}

=method info

  Usage       : $crRNA->info;
  Purpose     : return info about a crRNA
				name chr start end strand score sequence forward oligo reverse oligo
				off_target_score seed_score seed_hits exonerate_score exonerate_hits
				protein_coding_score protein_coding_scores_by_transcript
  Returns     : Array of Strings
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub info {
    my ( $self, ) = @_;
    
    my @info = (
        $self->name,
        $self->chr || 'NULL',
        $self->start,
        $self->end,
        $self->strand,
    );
	#score
    if( defined $self->score ){
        push @info, $num->format_number($self->score);
    }
    else{
        push @info, 'NULL';
    }
    push @info, $self->sequence, $self->forward_oligo, $self->reverse_oligo;
    
	# off-target score
    if( defined $self->off_target_hits ){
        push @info, $self->off_target_info;
    }
	else{
		push @info, qw{NULL NULL NULL NULL NULL };
	}
    
	# protein-coding score and detail on protein-coding scores by transcript
	if( defined $self->coding_score ){
		push @info, $num->format_number($self->coding_score), join(';', $self->coding_scores_by_transcript);
    }
    else{
        push @info, qw{NULL NULL};
    }
    
	push @info, $self->five_prime_Gs, $self->plasmid_backbone;
    return @info;
}

=method target_info_plus_crRNA_info

  Usage       : $crRNA->target_info_plus_crRNA_info;
  Purpose     : return info about a target and a crRNA
				target_info: target_id name assembly chr start end strand species
				requires_enzyme gene_id gene_name requestor ensembl_version designed
				crRNA info: name chr start end strand score
				sequence forward oligo reverse oligo
				off_target_score seed_score seed_hits exonerate_score exonerate_hits
				protein_coding_score protein_coding_scores_by_transcript
  Returns     : Array of Strings
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub target_info_plus_crRNA_info {
    my ( $self, ) = @_;
	
    if( !defined $self->target ){
		confess "crRNA does not have an associated Target!\n";
	}
	else{
		return ( $self->target_info, $self->info );
	}
}

=method target_summary_plus_crRNA_info

  Usage       : $crRNA->target_summary_plus_crRNA_info;
  Purpose     : return a target summary and crRNA info
				target_info: name gene_id gene_name requestor
				crRNA info: name chr start end strand score
				sequence forward oligo reverse oligo
				off_target_score seed_score seed_hits exonerate_score exonerate_hits
				protein_coding_score protein_coding_scores_by_transcript
  Returns     : Array of Strings
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub target_summary_plus_crRNA_info {
    my ( $self, ) = @_;
	# target info
    if( !defined $self->target ){
		confess "crRNA does not have an associated Target!\n";
    }
    else{
        return ( $self->target_summary, $self->info );
    }
}

=method cut_site

  Usage       : $crRNA->cut_site;
  Purpose     : Getter for the putative cut_site of the crRNA
  Returns     : Num
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub cut_site {
    my ( $self, ) = @_;
    return $self->strand eq '1'		?	$self->end - 6	: $self->start + 5;
}

=method coding_score_for

  Usage       : $crRNA->coding_score_for( $transcript );
  Purpose     : Getter/Setter for the coding score for a particular transcript
  Returns     : Num
  Parameters  : Bio::EnsEMBL::Transcript
  Throws      : 
  Comments    : 

=cut

sub coding_score_for {
    my ( $self, $transcript_id, $score ) = @_;
    
	#should check transcript id
    my $coding_scores_for = $self->coding_scores;
    if( defined $score ){
        $coding_scores_for->{$transcript_id} = $score;
        $self->_set_coding_scores( $coding_scores_for );
        return 1;
    }
    else{
        return $coding_scores_for->{ $transcript_id };
    }
}

=method coding_scores_by_transcript

  Usage       : $crRNA->coding_scores_by_transcript;
  Purpose     : Returns the coding scores for all transcripts
  Returns     : Array of Strings
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub coding_scores_by_transcript {
    my ( $self, ) = @_;
    my $scores = $self->coding_scores;
    my @scores;
    foreach ( keys %{$scores} ){
        push @scores, join('=', $_, $num->format_number($scores->{$_}) );
    }
    return @scores;
}

=method name

  Usage       : $crRNA->name;
  Purpose     : Returns a name for the crRNA, composed of:
				chr/target_gene_name:start-end:strand
  Returns     : String
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub name{
    my ( $self, ) = @_;
    my $name = 'crRNA:';
    
    if( defined $self->chr ){
        $name .= $self->chr . ':';
    }
    elsif( defined $self->target && defined $self->target_gene_name ){
        $name .= $self->target_gene_name . ':';
    }
    
    $name .= join(':',
        join('-', $self->start, $self->end, ),
        $self->strand,
    );
    return $name;
}

#_build_species
#
#Usage       : $crRNA->_build_species;
#Purpose     : builder for species attribute
#				tries to get species from Target if defined
#				otherwise returns undef
#Returns     : String
#Parameters  : None
#Throws      : 
#Comments    :

sub _build_species {
    my ( $self, ) = @_;
    if( $self->target ){
        return $self->target->species;
    }
    else{
        return undef;
    }
}

#_build_five_prime_Gs
#
#Usage       : $crRNA->_build_five_prime_Gs;
#Purpose     : builder for five_prime_Gs attribute
#				picks most likely number based on species
#				if no species returns 1
#Returns     : Int (EITHER 1 or 2)
#Parameters  : None
#Throws      : 
#Comments    :

sub _build_five_prime_Gs {
	my ( $self, ) = @_;
	my %five_prime_Gs_for = (
		'zebrafish' => 2,
		'human' => 1,
		'mouse' => 1,
	);
	if( $self->species ){
		if( exists $five_prime_Gs_for{$self->species} ){
			return $five_prime_Gs_for{$self->species};
		}
		else{
			return 0;
		}
	}
    else{
        return 0;
    }
}

=method core_sequence

  Usage       : $crRNA->core_sequence;
  Purpose     : Getter for core_sequence attribute
				core_sequence is crRNA seq without five prime Gs or PAM
  Returns     : String
  Parameters  : None
  Throws      : If sequence attribute is undef or empty
  Comments    : 

=cut

sub core_sequence {
    my ( $self, ) = @_;
    
    if( $self->sequence ){
		my $offset = $self->five_prime_Gs;
		my $length = length( $self->sequence ) - 3 - $self->five_prime_Gs;
        return substr( $self->sequence, $offset, $length );
    }
    else{
        # complain
		confess "Can't produce core sequence without a crRNA sequence!\n";
    }
}

#_build_oligo
#
#Usage       : $crRNA->_build_oligo;
#Purpose     : builder for construction oligos with appropriate overhangs
#Returns     : String
#Parameters  : (String, String)
#Throws      : 
#Comments    : warns if cannot determin the correct overhanges

sub _build_oligo {
    my ( $self, $oligo_seq, $type ) = @_;
    
	# MAY BE ABLE TO CHANGE THIS TO CHECKING PLASMID BACKBONE ATTRIBUTE - CHECK
    my %five_prime_nuc_for = (
        zebrafish_2G_forward => 'TAGG',
        zebrafish_2G_reverse => 'AAAC',
        zebrafish_1G_forward => 'ATAG',
        zebrafish_1G_reverse => 'AAAC',
        zebrafish_0G_forward => 'TAGG',
        zebrafish_0G_reverse => 'AAAC',
        human_1G_forward => 'ACCG',
        human_1G_reverse => 'AAAC',
        human_0G_forward => 'ACCG',
        human_0G_reverse => 'AAAC',
        mouse_1G_forward => 'ACCG',
        mouse_1G_reverse => 'AAAC',
        mouse_0G_forward => 'ACCG',
        mouse_0G_reverse => 'AAAC',
        xenopus_tropicalis_2G_forward => 'TAGG',
        xenopus_tropicalis_2G_reverse => 'AAAC',
        xenopus_tropicalis_1G_forward => 'ATAG',
        xenopus_tropicalis_1G_reverse => 'AAAC',
        xenopus_tropicalis_0G_forward => 'TAGG',
        xenopus_tropicalis_0G_reverse => 'AAAC',
    );
    
    if( $self->species ){
        my $five_prime_nuc;
		my $key = $self->species . '_' . $self->five_prime_Gs . 'G_' . $type;
        if( !exists $five_prime_nuc_for{$key} ){
            warn "Can't find five-prime nucleotides for species, ", $self->species, '. Using parameters for human...', "\n";
            $five_prime_nuc = $five_prime_nuc_for{'human_1G_' . $type};
        }
        else{
            $five_prime_nuc = $five_prime_nuc_for{ $key };
        }
        return $five_prime_nuc . $oligo_seq;
    }
    else{
        confess "Can't produce oligo without a species!\n";
    }
}

=method forward_oligo

  Usage       : $crRNA->forward_oligo;
  Purpose     : Getter for forward_oligo attribute
  Returns     : String
  Parameters  : None
  Throws      : If sequence attribute is undef or empty
  Comments    : 

=cut

sub forward_oligo {
    my ( $self, ) = @_;
    
    if( $self->sequence ){
        return $self->_build_oligo( $self->core_sequence, 'forward' );
    }
    else{
        confess "Can't produce oligo without a crRNA sequence!\n";
    }
}

=method reverse_oligo

  Usage       : $crRNA->reverse_oligo;
  Purpose     : Getter for reverse_oligo attribute
  Returns     : String
  Parameters  : None
  Throws      : If sequence attribute is undef or empty
  Comments    : 

=cut

sub reverse_oligo {
    my ( $self, ) = @_;
    
    if( $self->sequence ){
        my $rev_seq = scalar reverse( $self->core_sequence );
        $rev_seq =~ tr/ACGT/TGCA/;
        return $self->_build_oligo( $rev_seq, 'reverse' );
    }
    else{
        confess "Can't produce oligo without a crRNA sequence!\n";
    }
}

=method t7_hairpin_oligo

  Usage       : $crRNA->t7_hairpin_oligo;
  Purpose     : Getter for t7_hairpin_oligo attribute
  Returns     : String
  Parameters  : None
  Throws      : If sequence attribute is undef or empty
  Comments    : 

=cut

sub t7_hairpin_oligo {
	my ( $self, ) = @_;
	my $five_prime_sequence = 'CAAAACAGCATAGCTCTAAAAC';
	my $t7_hairpin = 'CCTATAGTGAGTCGTATTAACAACATAATACGACTCACTATAGG';
	
    if( $self->sequence ){
        my $rev_comp_seq = uc scalar reverse( $self->core_sequence );
        $rev_comp_seq =~ tr/ACGT/TGCA/;
		return $five_prime_sequence . $rev_comp_seq . $t7_hairpin;
    }
    else{
        confess "Can't produce oligo without a crRNA sequence!\n";
    }
	
}

#_build_backbone
#
#Usage       : $crRNA->_build_backbone;
#Purpose     : builder for plasmid_backbone attribute
#				picks most likely vector based on species and five_prime_Gs attributes
#				if cannot determin vector returns 'pGERETY-1261'
#Returns     : String (EITHER 'pGERETY-1261','pGERETY-1260', OR 'pDR274')
#Parameters  : None
#Throws      : 
#Comments    :

sub _build_backbone {
	my ( $self, ) = @_;
	my %plasmids_for = (
		zebrafish_2G => 'pDR274',
		zebrafish_1G => 'pGERETY-1260',
		zebrafish_0G => 'pDR274',
		human_1G => 'pGERETY-1261',
		human_0G => 'pGERETY-1261',
		mouse_1G => 'pGERETY-1261',
		mouse_0G => 'pGERETY-1261',
	);
	
	my $plasmid;
	if( $self->species ){
		my $key = $self->species . '_' . $self->five_prime_Gs . 'G';
		if( exists $plasmids_for{$key} ){
			$plasmid = $plasmids_for{$key};
		}
	}
	
	if( !$plasmid ){
		warn $self->name, " - Cannot determine vector backbone from species. Guessing pGERETY-1261.\n";
		$plasmid = 'pGERETY-1261';
	}

	return $plasmid;
}

=method coding_score

  Usage       : $crRNA->coding_score;
  Purpose     : Getter for coding score
				Average of coding scores for all transcripts
  Returns     : Float
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub coding_score {
    my ( $self, ) = @_;
    my $coding_scores_for = $self->coding_scores;
    
    if( !keys %{$coding_scores_for} ){
        return undef;
    }
    else{
        my ( $num_transcripts, $sum );
        foreach my $transcript_id ( keys %{$coding_scores_for} ){
            $num_transcripts++;
            $sum += $coding_scores_for->{$transcript_id};
        }
        return $sum/$num_transcripts;
    }
}

=method score

  Usage       : $crRNA->score;
  Purpose     : Getter for overall score
				Cobination of coding_score and off_target_score
  Returns     : Float
  Parameters  : None
  Throws      : 
  Comments    : 

=cut

sub score {
    my ( $self, ) = @_;
    
    my $score = defined $self->coding_score &&
					defined $self->off_target_hits &&
					defined $self->off_target_hits->score		?   $self->coding_score * $self->off_target_hits->score
        :       defined $self->coding_score              		?   $self->coding_score
        :       defined $self->off_target_hits &&
					defined $self->off_target_hits->score		?   $self->off_target_hits->score
        :                                                      	undef
        ;
    if( defined $score && ($score < 0 || $score > 1) ){
        $score = 0;
    }
    
    return $score;
}
__PACKAGE__->meta->make_immutable;
1;

#my $crRNA = Crispr::crRNA->new(
#	crRNA_id => undef,
#	target => $target,
#	chr => '5',
#	start => 20103030,
#	end => 20103930,
#	strand => '1',
#	sequence => 'GAGATAGACATAGACAGTCGG',
#	species => 'zebrafish',
#	off_target_hits => $off_target_hits,
#	coding_scores => $HashRef,
#	unique_restriction_sites => $enzyme_collection,
#	primer_pairs => $primer_pairs,
#	crRNA_adaptor => $crRNA_adaptor,
#);


