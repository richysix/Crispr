## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr;
## use critic

# ABSTRACT: Crispr object - used for designing crispr guide RNAs

use warnings;
use strict;
use autodie qw(:all);
use List::MoreUtils qw( any );
use Carp;

use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use Crispr::crRNA;
use Crispr::Target;
use Tree::Annotation;
use Tree::GenomicInterval;

use Bio::Seq;
use Bio::SeqIO;

subtype 'Crispr::DNA',
    as 'Str',
    where { 
        m/\A [ACGTNRYSWMKBDHV]+ \z/xms;
    },
    message { "Not a valid crRNA target sequence.\n" };

subtype 'Crispr::FileExists',
    as 'Str',
    where { 
        ( -e $_ && !-z $_ );
    },
    message { "File does not exist or is empty.\n" };

=method new

  Usage       : my $crispr_design = Crispr->new(
                    species => 'zebrafish',
                    target_seq => 'NNNNNNNNNNNNNNNNNNNNNGG',
                    PAM => 'NGG',
                    five_prime_Gs => 0,
                    target_genome => 'target_genome.fa',
                    slice_adaptor => $slice_adaptor,
                    targets => $targets,
                    all_crisprs => $all_crisprs,
                    annotation_file => 'annotation.gff',
                    annotation_tree => $tree,
                    off_targets_interval_tree => $off_tree,
                    debug => 0,
                );
  Purpose     : Constructor for creating Crispr objects
  Returns     : Crispr object
  Parameters  : species => String
                target_seq => Crispr::DNA
                PAM => Crispr::DNA
                five_prime_Gs => 0, 1 OR 2
                target_genome => String,
                slice_adaptor => Bio::EnsEMBL::DBSQL::SliceAdaptor,
                targets => ArrayRef of Crispr::Target objects,
                all_crisprs => HashRef of Crispr::crRNA objects,
                annotation_file => String,
                annotation_tree => Tree::Annotation,
                off_targets_interval_tree => Tree::GenomicInterval,
                debug => Int,
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method target_seq

  Usage       : $crispr_design->target_seq;
  Purpose     : Getter for target_seq attribute
  Returns     : Str (must be a valid DNA string)
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'target_seq' => (
    is => 'ro',
    isa => 'Crispr::DNA',
);

=method PAM

  Usage       : $crispr_design->PAM;
  Purpose     : Getter for PAM attribute
  Returns     : String
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'PAM' => (
    is => 'ro',
    isa => 'Crispr::DNA',
);

=method five_prime_Gs

  Usage       : $crispr_design->five_prime_Gs;
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

=method species

  Usage       : $crispr_design->species;
  Purpose     : Getter for species attribute
  Returns     : String
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'species' => (
    is => 'ro',
    isa => 'Str',
);

=method target_genome

  Usage       : $crispr_design->target_genome;
  Purpose     : Getter for target_genome attribute
  Returns     : Str
  Parameters  : None
  Throws      : If input is given.
                If file does not exist or is empty.
  Comments    : 

=cut

has 'target_genome' => (
    is => 'ro',
    isa => 'Crispr::FileExists',
);

=method slice_adaptor

  Usage       : $crispr_design->slice_adaptor;
  Purpose     : Getter for slice_adaptor attribute
  Returns     : Bio::EnsEMBL::DBSQL::SliceAdaptor
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'slice_adaptor' => (
    is => 'ro',
    isa => 'Bio::EnsEMBL::DBSQL::SliceAdaptor',
);

=method targets

  Usage       : $crispr_design->targets;
  Purpose     : Getter for targets attribute
  Returns     : String
  Parameters  : None
  Throws      : If input is given
  Comments    : Hash keys should be target names

=cut

has 'targets' => (
    is => 'ro',
    isa => 'ArrayRef[Crispr::Target]',
    writer => '_set_targets',
);

=method all_crisprs

  Usage       : $crispr_design->all_crisprs;
  Purpose     : Getter for all_crisprs attribute
  Returns     : String
  Parameters  : None
  Throws      : If input is given
  Comments    : Hash keys are combination of crRNA name and Target name

=cut

has 'all_crisprs' => (
    is => 'ro',
    isa => 'HashRef[Crispr::crRNA]',
    writer => '_set_all_crisprs',
);

=method annotation_file

  Usage       : $crispr_design->annotation_file;
  Purpose     : Getter for annotation_file attribute
  Returns     : String
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'annotation_file' => (
    is => 'ro',
    isa => 'Str',
);

=method annotation_tree

  Usage       : $crispr_design->annotation_tree;
  Purpose     : Getter for annotation_tree attribute
  Returns     : Tree::AnnotationTree
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'annotation_tree' => (
    is => 'ro',
    isa => 'Tree::Annotation',
    builder => '_build_annotation_tree',
    lazy => 1,
);

=method off_targets_interval_tree

  Usage       : $crispr_design->off_targets_interval_tree;
  Purpose     : Getter for off_targets_interval_tree attribute
  Returns     : Set::GenomicTree
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'off_targets_interval_tree' => (
    is => 'ro',
    isa => 'Tree::GenomicInterval',
    builder => '_build_interval_tree',
    lazy => 1,
);

=method debug

  Usage       : $crispr_design->debug;
  Purpose     : Getter for debug attribute
  Returns     : String
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

has 'debug' => (
    is => 'ro',
    isa => 'Int',
);

# This hash is used to keep track of crRNAs for every target
# keys are concatenated crRNA name and Target name
my $crRNA_seen = {};
my $target_seen = {};

#_seen_crRNA_id
#
#Usage       : $crRNA->_seen_crRNA_id;
#Purpose     : Internal method for checking if a particular crRNA has been seen before
#Returns     : 1 if crRNA has been seen before, 0 otherwise
#Parameters  : crRNA name
#              Target name
#Throws      : 
#Comments    : 

sub _seen_crRNA_id {
	my ( $self, $name, $target_name ) = @_;
	if( exists $crRNA_seen->{$name . q{_} . $target_name} ){
		return 1;
	}
	else{
		$crRNA_seen->{$name . q{_} . $target_name} = 1;
		return 0;
	}
}

#_seen_target_name
#
#Usage       : $crRNA->_seen_target_name;
#Purpose     : Internal method to check whether a given Target name has been seen before
#Returns     : 1 if Target name has been seen before, 0 otherwise
#Parameters  : Target name
#Throws      : 
#Comments    : 

sub _seen_target_name {
	my ( $self, $name ) = @_;
	if( exists $target_seen->{$name} ){
		return 1;
	}
	else{
		$target_seen->{$name} = 1;
		return 0;
	}
}

=method find_crRNAs_by_region

  Usage       : $crispr_design->find_crRNAs_by_region( '1:1000-1500:1', $target );
  Purpose     : method to find possible crRNA target sites given a region and a target sequence
  Returns     : ArrayRef of Crispr::crRNA objects
  Parameters  : Region (Str) CHR:START-END:STRAND (STRAND is not essential)
				Crispr::Target (optional)
  Throws      : If either region or $self->target_seq are undef
				If Region is not of the form CHR:START-END or CHR:START-END:STRAND
  Comments    : Only crRNAs with cut-sites inside the target region are retained

=cut

sub find_crRNAs_by_region {
	my ( $self, $region, $target ) = @_;
	
	if( !defined $region ){
		confess "A region must be supplied to find_crRNAs_by_region!\n";
	}
	if( !defined $self->target_seq ){
		confess "The target_seq attribute must be defined to search for crRNAs!\n";
	}
    # get target name. If no target, use region as name.
    my $target_name = defined $target   ?   $target->name   :   $region;
    
	my @crRNAs;
    # create regex from target sequence for forward and reverse
	my $f_regex = $self->_construct_regex_from_target_seq( $self->target_seq );
	warn $f_regex, "\n" if $self->debug == 2;
	my $r_str = reverse $self->target_seq;
	$r_str =~ tr/[ACGTNRYSWMKBDHV]/[TGCANYRWSKMVHDB]/;
	my $r_regex = $self->_construct_regex_from_target_seq( $r_str );
	warn $r_regex, "\n" if $self->debug == 2;
	
	# fetch region from Ensembl
	my ( $chr, $interval, $strand ) = split /:/, $region;
	if( !$chr || !$interval ){
		confess "Couldn't understand region - $region.\n";
	}
	my ( $start, $end ) = split /-/, $interval;
	my $slice = $self->slice_adaptor->fetch_by_region( 'toplevel', $chr, $start, $end, '1' );
	# expand slice by length of target sequence
	my $expanded_slice = $slice->expand( $self->target_seq_length, $self->target_seq_length );
	my $match_start = $expanded_slice->start;
	my $match_end = $expanded_slice->end;
    my $search_seq = $expanded_slice->seq;
	warn $search_seq, "\n" if $self->debug == 2;
    # search sequence for forward regex
    while( $search_seq =~ m/$f_regex/g ){
        # remove crisprs with transcriptional stop sequence
        next if( $1 =~ m/T{5}/xms );
        # remove crisprs with DraI sequence if they are for fish
        ## TO DO: make this based on something else like plasmid
        if( $self->species eq 'zebrafish' ){
            next if( $1 =~ m/TTTAAA/xms );
        }
        my $match_offset = pos($search_seq);
		# make a new crRNA object
		my $crRNA = Crispr::crRNA->new(
			chr => $chr,
			start => $match_offset + $match_start,
			end => $match_offset + $match_start + $self->target_seq_length,
			strand => '1',
			sequence => $1,
			species => $self->species,
			five_prime_Gs => $self->five_prime_Gs,
		);
        # add Target object if it exists
		$crRNA->target( $target ) if $target;
        # check if crispr already exists for this target
		next if( $self->_seen_crRNA_id( $crRNA->name, $target_name ) );
		next if( $crRNA->cut_site < $start || $crRNA->cut_site > $end );
		push @crRNAs, $crRNA;
        warn $1, "\t", $match_offset, "\n", if $self->debug == 2;
    }
    
    while( $search_seq =~ m/$r_regex/g ){
        next if( $1 =~ m/A{5}/xms );
        if( $self->species eq 'zebrafish' ){
            next if( $1 =~ m/TTTAAA/xms );
        }
        my $match_offset = pos($search_seq);
        my $rev_com_seq = reverse $1;
        $rev_com_seq =~ tr/[ACGT]/[TGCA]/;
		# make a new crRNA object
		my $crRNA = Crispr::crRNA->new(
			chr => $chr,
			start => $match_offset + $match_start,
			end => $match_offset + $match_start + 22,
			strand => '-1',
			sequence => $rev_com_seq,
			species => $self->species,
			five_prime_Gs => $self->five_prime_Gs,
		);
		$crRNA->target( $target ) if $target;
		next if( $self->_seen_crRNA_id( $crRNA->name, $target_name ) );
		next if( $crRNA->cut_site < $start || $crRNA->cut_site > $end );
		push @crRNAs, $crRNA;
        warn $1, "\t", $match_offset, "\n", if $self->debug == 2;
    }
	
	$self->add_crisprs( \@crRNAs, $target_name );
	return \@crRNAs;
}

sub _construct_regex_from_target_seq {
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

=method find_crRNAs_by_target

  Usage       : $crispr_design->find_crRNAs_by_target( $target );
  Purpose     : method to find possible crRNA target sites given a Crispr::Target object
  Returns     : ArrayRef of Crispr::crRNA objects
  Parameters  : Crispr::Target
  Throws      : If Target not supplied.
                If the Target has already been seen before.
  Comments    : Only crRNAs with cut-sites inside the target region are retained

=cut

sub find_crRNAs_by_target {
	my ( $self, $target, ) = @_;
	if( !defined $target ){
		confess "A Crispr::Target must be supplied to find_crRNAs_by_target!\n";
	}
    if( !$target->isa('Crispr::Target') ){
        confess "A Crispr::Target object is required for find_crRNAs_by_target",
            "not a ", ref $target, ".\n";
    }
	if( $self->_seen_target_name( $target->name ) ){
		confess "This target, ", $target->name,", has been seen before.\n";
	}
	my $crRNAs = $self->find_crRNAs_by_region( $target->region, $target );
	$self->add_target( $target );
    $target->crRNAs( $crRNAs );
	return $crRNAs;
}

=method filter_crRNAs_from_target_by_strand

  Usage       : $crispr_design->filter_crRNAs_from_target_by_strand( $target, '1' );
  Purpose     : method to keep only crRNAs on a given strand
  Returns     : ArrayRef of Crispr::crRNA objects
  Parameters  : Crispr::Target
                Str ('1' or '-1')
  Throws      : If Target not supplied.
                If strand not valid.
  Comments    : 

=cut

sub filter_crRNAs_from_target_by_strand {
    my ( $self, $target, $strand_to_keep, ) = @_;
	
	my @crRNAs_to_keep;
	my @crRNAs_to_delete;
	my $crRNAs = $target->crRNAs;
	foreach my $crRNA ( @{$crRNAs} ){
		if( $crRNA->strand eq $strand_to_keep ){
			push @crRNAs_to_keep, $crRNA;
		}
		else{
			push @crRNAs_to_delete, $crRNA;
		}
	}
	
	$target->crRNAs( \@crRNAs_to_keep );
	$self->remove_crisprs( \@crRNAs_to_delete );
	return \@crRNAs_to_keep;
}

=method filter_crRNAs_from_target_by_score

  Usage       : $crispr_design->filter_crRNAs_from_target_by_score( $target, $number_to_keep );
  Purpose     : method to keep only the top scoring crRNAs
  Returns     : ArrayRef of Crispr::crRNA objects
  Parameters  : Crispr::Target
                Int (Number of crRNAs to keep)
  Throws      : If Target not supplied.
                If num_to_keep not an Int
  Comments    : 

=cut

sub filter_crRNAs_from_target_by_score {
    my ( $self, $target, $num_to_keep, ) = @_;
	
	my @crRNAs_to_keep;
	my @crRNAs_to_delete;
	my $crRNAs = $target->crRNAs;
	foreach my $crRNA ( sort { $b->score <=> $a->score } @{$crRNAs} ){
		if( scalar @crRNAs_to_keep < $num_to_keep ){
			push @crRNAs_to_keep, $crRNA;
		}
		else{
			push @crRNAs_to_delete, $crRNA;
		}
	}
	$target->crRNAs( \@crRNAs_to_keep );
	$self->remove_crisprs( \@crRNAs_to_delete );
	return \@crRNAs_to_keep;
}

=method add_targets

  Usage       : $crispr_design->add_targets( $targets, );
  Purpose     : method to add targets to targets attribute
  Returns     : 1 on Success
  Parameters  : ArrayRef of Crispr::Target objects
                Int (Number of crRNAs to keep)
  Throws      : If parameter not an ArrayRef
                If one of the objects in the Array is not a Target object
  Comments    : 

=cut

sub add_targets {
	my ( $self, $targets ) = @_;
	
	# check $targets is an arrayref of Targets
    if( !ref $targets || ref $targets ne 'ARRAY' ){
        confess "The supplied argument is not an ArrayRef!\n";
    }
    foreach ( @{$targets} ){
        if( !ref $_ || !$_->isa('Crispr::Target') ){
            confess "One of the supplied objects is not a Crispr::Target object, it's a ",
                ref $_, ".\n";
        }
    }
	
	my $targets_ref = $self->targets;
	$targets_ref = [] if( !defined $targets_ref );
	foreach my $target ( @{$targets} ){
		push @{ $targets_ref }, $target;
	}
	$self->_set_targets( $targets_ref );
    
    return 1;
}

=method add_target

  Usage       : $crispr_design->add_target( $target, );
  Purpose     : method to add a target to targets attribute
  Returns     : 1 on Success
  Parameters  : Crispr::Target
  Throws      : If supplied object is not a Crispr::Target.
  Comments    : 

=cut

sub add_target {
	my ( $self, $target ) = @_;
	if( !ref $target || !$target->isa('Crispr::Target') ){
		confess "The supplied object is not a Crispr::Target object, it's a ",
                ref $target, ".\n";
	}
	$self->add_targets( [ $target ] );
}

=method remove_target

  Usage       : $crispr_design->remove_target( $target, );
  Purpose     : method to remove a target from the targets attribute
  Returns     : 1 on Success
  Parameters  : Crispr::Target
  Throws      : If supplied object is not a Crispr::Target.
  Comments    : 

=cut

sub remove_target {
	my ( $self, $target ) = @_;
	if( !ref $target || !$target->isa('Crispr::Target') ){
		confess "The supplied object is not a Crispr::Target object, it's a ",
                ref $target, ".\n";
	}
	my @targets_to_keep = grep { $_->name ne $target->name } @{$self->targets};
	$self->_set_targets( \@targets_to_keep );
    
    return 1;
}

=method add_crisprs

  Usage       : $crispr_design->add_crisprs( $crRNAs, );
  Purpose     : method to add crisprs to all_crisprs attribute
  Returns     : 1 on Success
  Parameters  : ArrayRef/HashRef of Crispr::crRNA objects
                Target name (optional)
  Throws      : If parameter not an ArrayRef or HashRef
                If one of the objects is not a Crispr::crRNA object
                If no target name is supplied and any of the Crispr::crRNA objects do not have a Target
  Comments    : 

=cut

sub add_crisprs {
	my ( $self, $crRNAs, $target_name, ) = @_;
	
	# check $crRNAs is either an arrayref or a hashref of crRNAs
    if( !ref $crRNAs ){
        confess "The supplied argument is neither an ArrayRef or a HashRef!\n";
    }
	if( ref $crRNAs eq 'ARRAY' ){
		foreach ( @{$crRNAs} ){
			if( !ref $_ || !$_->isa('Crispr::crRNA') ){
				confess "One of the supplied objects is not a Crispr::crRNA object, it's a ",
					ref $_, ".\n";
			}
		}
		
		# check all crRNAs have a target
		if( !$target_name && any { !defined $_->target } @{$crRNAs} ){
			confess "Method: add_crisprs - Each crRNA must have an associated target or a target name must be supplied for all supplied crRNAs!\n";
		}
		my $crispr_ref = $self->all_crisprs;
		$crispr_ref = {} if( !defined $crispr_ref );
		foreach my $crRNA ( @{$crRNAs} ){
            $target_name = !$target_name    ?   $crRNA->target->name
                :                               $target_name;
			$crispr_ref->{$crRNA->name . q{_} . $target_name} = $crRNA;
		}
		$self->_set_all_crisprs( $crispr_ref );
	}
	elsif( ref $crRNAs eq 'HASH' ){
		foreach ( keys %{$crRNAs} ){
			if( !ref $crRNAs->{$_} || !$crRNAs->{$_}->isa('Crispr::crRNA') ){
				confess "One of the supplied objects is not a Crispr::crRNA object, it's a ",
					ref $crRNAs->{$_}, ".\n";
			}
		}
		
		# check all crRNAs have a target
		if( !$target_name && any { !defined $crRNAs->{$_}->target } keys %{$crRNAs} ){
			confess "Method: add_crisprs - Each crRNA must have an associated target or a target name must be supplied for all supplied crRNAs!\n";
		}
		my $crispr_ref = $self->all_crisprs;
		$crispr_ref = {} if( !defined $crispr_ref );
		foreach my $crRNA_name ( keys %{$crRNAs} ){
            my $crRNA = $crRNAs->{$crRNA_name};
            $target_name = !$target_name    ?   $crRNA->target->name
                :                               $target_name;
			$crispr_ref->{$crRNA_name . q{_} . $target_name} = $crRNA;
		}
		$self->_set_all_crisprs( $crispr_ref );
	}
	else{
        confess "The supplied argument is neither an ArrayRef or a HashRef!\n";
	}
}

=method remove_crisprs

  Usage       : $crispr_design->remove_crisprs( $crRNAs, );
  Purpose     : method to remove crisprs from all_crisprs attribute
  Returns     : 1 on Success
  Parameters  : ArrayRef/HashRef of Crispr::crRNA objects
  Throws      : If parameter not an ArrayRef or HashRef
                If one of the objects is not a Crispr::crRNA object
                If any of the Crispr::crRNA objects do not have a Target
  Comments    : 

=cut

sub remove_crisprs {
	my ( $self, $crRNAs ) = @_;
	
	# check $crRNAs is either an arrayref or hashref of crRNAs
    if( !ref $crRNAs ){
        confess "The supplied argument is neither an ArrayRef or a HashRef!\n";
    }
	if( ref $crRNAs eq 'ARRAY' ){
		foreach ( @{$crRNAs} ){
			if( !ref $_ || !$_->isa('Crispr::crRNA') ){
				confess "One of the supplied objects is not a Crispr::crRNA object, it's a ",
					ref $_, ".\n";
			}
		}
		
		# check all crRNAs have a target
		if( any { !defined $_->target } @{$crRNAs} ){
			confess "Each crRNA must have an associated target!\n";
		}
		my $crispr_ref = $self->all_crisprs;
		$crispr_ref = {} if( !defined $crispr_ref );
		foreach my $crRNA ( @{$crRNAs} ){
			delete $crispr_ref->{$crRNA->name . q{_} . $crRNA->target->name};
		}
		$self->_set_all_crisprs( $crispr_ref );
	}
	elsif( ref $crRNAs eq 'HASH' ){
		foreach ( keys %{$crRNAs} ){
			if( !ref $_ || !$_->isa('Crispr::crRNA') ){
				confess "One of the supplied objects is not a Crispr::crRNA object, it's a ",
					ref $_, ".\n";
			}
		}
		
		# check all crRNAs have a target
		if( any { !defined $crRNAs->{$_}->target } keys %{$crRNAs} ){
			confess "Each crRNA must have an associated target!\n";
		}
		my $crispr_ref = $self->all_crisprs;
		$crispr_ref = {} if( !defined $crispr_ref );
		foreach my $crRNA_name ( keys %{$crRNAs} ){
            my $crRNA = $crRNAs->{$crRNA_name};
			delete $crispr_ref->{$crRNA_name . q{_} . $crRNA->target->name};
		}
		$self->_set_all_crisprs( $crispr_ref );
	}
	else{
        confess "The supplied argument is neither an ArrayRef or a HashRef!\n";
	}
}

=method target_seq_length

  Usage       : $crRNA->_build_target_seq_length;
  Purpose     : Getter for target_seq_length attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given
  Comments    : 

=cut

my $target_seq_length;
sub target_seq_length {
    my ( $self, $input, ) = @_;
    
    if( $input ){
        confess "target_seq_length is a read-only attribute. It cannot be set.\n";
    }
    if( !$target_seq_length ){
        $target_seq_length = length $self->target_seq;
    }
    return $target_seq_length
}

=method create_crRNA_from_crRNA_name

  Usage       : $crispr->create_crRNA_from_crRNA_name( 'crRNA:CHR:START-END:STRAND', $species, );
  Purpose     : Create a new minimal crRNA object from a crRNA name
  Returns     : Crispr::crRNA object
  Parameters  : valid crRNA name    String
                species: optional
  Throws      : If crRNA name is not valid
  Comments    : 

=cut

sub create_crRNA_from_crRNA_name {
    my ( $self, $name, $species, ) = @_;
    
    my ( $chr, $start, $end, $strand ) = $self->parse_cr_name( $name );
    my $crRNA = Crispr::crRNA->new(
        chr => $chr,
        start => $start,
        end => $end,
        strand => $strand || 1,
        species => $species || undef,
    );
    return $crRNA;
}

=method parse_cr_name

  Usage       : $crispr->parse_cr_name( $crRNA_name, );
  Purpose     : Parse a crRNA name to CHR, START, END, STRAND
  Returns     : CHR, START, END, STRAND
  Parameters  : valid crRNA name    String
  Throws      : If crRNA name is not valid
  Comments    : 

=cut

sub parse_cr_name {
    my ( $self, $cr_name, ) = @_;
    
    $cr_name =~ s/\AcrRNA://xms;
    my @info = split /:/, $cr_name;
    my ( $chr, $range, $strand );
    if( scalar @info == 3 ){
        ( $chr, $range, $strand ) = @info;
    }
    elsif( scalar @info == 2 ){
        ( $chr, $range ) = @info;
    }
    else{
        # complain
        confess "Could not understand crRNA name. Should at least be crRNA:CHR:START-END.\n";
    }
    my ( $start, $end ) = split /-/, $range;
    
    return ( $chr, $start, $end, $strand );
}

=method off_targets_bwa

  Usage       : $crispr->off_targets_bwa( $crRNAs, $basename, );
  Purpose     : Searches for potential off-target hits for crRNAs using bwa
  Returns     : ArrayRef of Crispr::crRNA objects
  Parameters  : ArrayRef of Crispr::crRNA objects
                Basename for tmp output files   (String)
  Throws      : 
  Comments    : TO DO: Need to do something about an undef basename

=cut

sub off_targets_bwa {
    my ( $self, $crRNAs, $basename, ) = @_;
    $self->output_fastq_for_off_targets( $crRNAs, $basename, );
    $self->bwa_align( $basename, );
    $self->make_bam_and_bed_files( $basename, );
    $self->filter_and_score_off_targets( $crRNAs, $basename, );
    return $crRNAs;
}

=method output_fastq_for_off_targets

  Usage       : $crispr->output_fastq_for_off_targets( $crRNAs, $basename, );
  Purpose     : Outputs a fastq file for off-target checking by bwa
  Returns     : 1 on Success
  Parameters  : ArrayRef of Crispr::crRNA objects
                Basename for tmp output files   (String)
  Throws      : 
  Comments    : 

=cut

sub output_fastq_for_off_targets {
    my ( $self, $crRNAs, $basename, ) = @_;
	
    my $crispr_fq_filename = $basename . '.fq';
    open my $fq_fh, '>', $crispr_fq_filename or confess "Couldn't open file, $crispr_fq_filename:$!\n";
    
	foreach my $crRNA_id ( keys %{$crRNAs} ){
		my $crRNA = $crRNAs->{$crRNA_id};
		print {$fq_fh} "@", $crRNA_id, "\n", $crRNA->sequence, "\n";
	}
    close $fq_fh;
	return 1;
}

=method bwa_align

  Usage       : $crispr->bwa_align( $basename, );
  Purpose     : Runs bwa aln to look for off-target hits
  Returns     : 1 on Success
  Parameters  : Basename for tmp output files   (String)
  Throws      : 
  Comments    : 

=cut

sub bwa_align {
	my ( $self, $basename, ) = @_;
	my $fq_filename = $basename . '.fq';
	my $sai_filename = $basename . '.sai';
	#my $align_cmd = join(q{ }, '/software/solexa/bin/bwa aln -n 6 -o 0 -l 20 -k 5 -N',
	#	$self->target_genome, $fq_filename, '>', $sai_filename, );
	my $align_cmd = join(q{ }, '/software/solexa/bin/bwa aln -n 4 -o 0 -l 20 -k 3 -N',
		$self->target_genome, $fq_filename, '>', $sai_filename, );
	system( $align_cmd );
    return 1;
}

=method make_bam_and_bed_files

  Usage       : $crispr->make_bam_and_bed_files( $basename, );
  Purpose     : Run bwa samse and bamtobed to create a bed file of off-target checking
  Returns     : 1 on Success
  Parameters  : Basename for tmp output files   (String)
  Throws      : 
  Comments    : 

=cut

sub make_bam_and_bed_files {
	my ( $self, $basename ) = @_;
	my $sam_cmd = join(q{ }, '/software/solexa/bin/bwa samse -n 900000',
		$self->target_genome, "$basename.sai", "$basename.fq",
		'| /software/solexa/pkg/bwa/current/xa2multi.pl ',
		'| /software/team31/bin/samtools view -bS - ',
		'| /software/team31/bin/samtools sort -', "$basename.sorted", );
	system( $sam_cmd );
	
	my $bed_cmd = join(q{ }, '/software/team31/bin/bedtools bamtobed',
		"-i $basename.sorted.bam", '>', "$basename.bed", );
	system( $bed_cmd );
    return 1;
}

=method filter_and_score_off_targets

  Usage       : $crispr->filter_and_score_off_targets( $crRNAs, $basename, );
  Purpose     : Run bwa samse and bamtobed to create a bed file of off-target checking
  Returns     : HashRef of Crispr::crRNA objects
  Parameters  : HashRef of Crispr::crRNA objects
                Basename for tmp output files   (String)
  Throws      : 
  Comments    : 

=cut

sub filter_and_score_off_targets {
	my ( $self, $crRNAs, $basename, ) = @_;
	open my $bed_fh, '<', "$basename.bed";
	while(<$bed_fh>){
		chomp;
		my ( $chr, $zero_start, $end, $id, undef, $strand_symbol, ) = split /\t/;
		my $strand = $strand_symbol eq '+'	?	'1'
			:									'-1';
		#get slice
		my $off_target_slice = $self->slice_adaptor->fetch_by_region( 'toplevel', $chr, $zero_start + 1, $end, $strand, );
		next if( $off_target_slice->seq !~ m/GG\z/xms || $off_target_slice->seq =~ m/N/xms );
		warn $crRNAs->{$id}->name, "\t", $off_target_slice->seq, "\t", $off_target_slice->strand, "\n" if( $self->debug == 2 );
		$crRNAs = $self->score_off_targets_from_bed_output( $crRNAs, $id, $chr, $zero_start + 1, $end, $strand, );
	}
	return $crRNAs;
}

=method score_off_targets_from_bed_output

  Usage       : $crispr->score_off_targets_from_bed_output( $crRNAs, $id, $chr, $start, $end, $strand, );
  Purpose     : Adds off-target info to crRNA objects and to off_targets_interval_tree
  Returns     : HashRef of Crispr::crRNA objects
  Parameters  : HashRef of Crispr::crRNA objects
                crRNA name  String
                CHR         String
                START       Int
                END         Int
                STRAND      String
  Throws      : 
  Comments    : 

=cut

sub score_off_targets_from_bed_output {
	my ( $self, $crRNAs, $id, $chr, $start, $end, $strand, ) = @_;
	
	return $crRNAs if( !exists $crRNAs->{$id} );
	my $crRNA = $crRNAs->{$id};
	
	if( !defined $crRNA->off_target_hits ){
		my $off_target_object = Crispr::OffTarget->new(
			crRNA_name => $crRNA->name,
			number_bwa_intron_hits => 0,
			number_bwa_nongenic_hits => 0,
			number_exonerate_intron_hits => 0,
			number_exonerate_nongenic_hits => 0,
			number_seed_intron_hits => 0,
			number_seed_nongenic_hits => 0,
            bwa_alignments => [],
            bwa_exon_alignments => [],
		);
		$crRNA->off_target_hits( $off_target_object );
	}
	#return $crRNAs if( $crRNA->off_target_hits->score < 0.001 );
	return $crRNAs if( defined $crRNA->chr && $crRNA->chr eq $chr && $crRNA->start == $start && $crRNA->end == $end );
	my $alignments_posn = $chr . ':' . $start . '-' . $end . ':' . $strand;
	# add to off-target object
	$crRNA->off_target_hits->bwa_alignments( $alignments_posn );
	
	# add to interval tree
	my $off_target_info = {
		crRNA_name => $id,
		chr => $chr,
		start => $start,
		end => $end,
		strand => $strand,
	};
	
	$self->off_targets_interval_tree->insert_interval_into_tree( $chr, $start, $end, $off_target_info );
	
	# check annotation
	my $annotations = $self->annotation_tree->fetch_overlapping_annotations( $chr, $start, $end );
	if( !@{$annotations} ){
		$crRNA->off_target_hits->increment_bwa_nongenic_hits;
	}
	elsif( any { $_ eq 'exon' } @{$annotations} ){
		$crRNA->off_target_hits->bwa_exon_alignments($alignments_posn);
	}
	elsif( any { $_ eq 'intron' } @{$annotations} ){
		$crRNA->off_target_hits->increment_bwa_intron_hits;
	}
	return $crRNAs;
}

=method calculate_all_pc_coding_scores

  Usage       : $crispr->calculate_all_pc_coding_scores( $crRNA, $transcripts );
  Purpose     : Calculates the position of a crRNA relative to the start of a set of transcripts and produces a score
  Returns     : HashRef of Crispr::crRNA objects
  Parameters  : Crispr::crRNA object
                ArrayRef of Bio::EnsEMBL::Transcript objects
  Throws      : 
  Comments    : 

=cut

sub calculate_all_pc_coding_scores{
	my ($self, $crRNA, $transcripts ) = @_;
	# get coding transcripts
	my @coding_transcripts = grep { $_->biotype() eq 'protein_coding' } @{$transcripts};
	
	my $num_transcripts = 0;
	foreach my $transcript ( @coding_transcripts ){
		$num_transcripts++;
		
		my $pc_coding_score = $self->calculate_pc_coding_score( $crRNA, $transcript );
		
		$crRNA->coding_score_for( $transcript->stable_id, $pc_coding_score );
	}
	return $crRNA;
}

=method calculate_all_pc_coding_scores

  Usage       : $crispr->calculate_all_pc_coding_scores( $crRNA, $transcripts );
  Purpose     : Calculates the position of a crRNA relative to the start of a transcript and produces a score
  Returns     : HashRef of Crispr::crRNA objects
  Parameters  : Crispr::crRNA object
                ArrayRef of Bio::EnsEMBL::Transcript objects
  Throws      : 
  Comments    : The score is the percentage of the protein removed by a premature stop at the crRNA cut-site
                i.e. 1 is the start of the transcript and 0 is the end

=cut

sub calculate_pc_coding_score {
	my ( $self, $crRNA, $transcript ) = @_;
	
    my $pos = $crRNA->cut_site;
    
    my $translation = $transcript->translation();
    next if !$translation;
    # Length
    my $translation_length = $translation->length;
    
    # Position in translation
    my $translation_pos;
    #my $new_transcript = $transcript_adaptor->fetch_by_stable_id($transcript->stable_id);
    my @coords = $transcript->genomic2pep($pos, $pos, $transcript->strand());
    foreach my $coord (@coords) {
        #print Dumper( $coord );
        next if !$coord->isa('Bio::EnsEMBL::Mapper::Coordinate');
        $translation_pos = $coord->start;
    }
    if (!$translation_pos) {
        # Extend positions to take accept crRNAs near coding sequence
        my @coords = $transcript->genomic2pep($pos - 10, $pos + 10, $transcript->strand());
        foreach my $coord (@coords) {
            #print Dumper( $coord );
            next if !$coord->isa('Bio::EnsEMBL::Mapper::Coordinate');
            $translation_pos = int(($coord->start + $coord->end)/2);
        }
    }
    
    my $pc_coding_score;
    if (!$translation_pos) {
        $pc_coding_score = 0;
    }
    else{
        $pc_coding_score = 1 - $translation_pos/$translation_length;
    }
	
	if( $pc_coding_score < 0 ){
		return 0;
	}
	else{
	    return $pc_coding_score;
	}
}

#_build_annotation_tree
#
#Usage       : $crRNA->_build_annotation_tree;
#Purpose     : builder for Annotation Tree to hold genome annotation
#Returns     : Tree::AnnotationTree
#Parameters  : None
#Throws      : 
#Comments    : 

sub _build_annotation_tree {
    my ( $self, ) = @_;
    
    my $tree;
    if( !$self->annotation_file ){
        confess "Cannot make an AnnotationTree without an annotation file!\n";
    }
    elsif( $self->annotation_file !~ m/\.gff\z/xms ){
        confess "The annotation file, ", $self->annotation_file, ", doesn't appear to be a gff file!\n";
    }
    elsif( !-e $self->annotation_file || -z $self->annotation_file ){
        confess "The annotation file for exon/intron annotation does not exist or is empty.\n";
    }
    else{
        # assume annotation is in gff format
        $tree = Tree::Annotation->new();
        $tree->add_annotations_from_gff( $self->annotation_file );
    }
    return $tree;
}

#_build_interval_tree
#
#Usage       : $crRNA->_build_interval_tree;
#Purpose     : builder for Genomic Interval Tree to hold crispr off-target hits
#Returns     : Tree::GenomicIntervalTree
#Parameters  : None
#Throws      : 
#Comments    : 

sub _build_interval_tree {
    my ( $self, ) = @_;
    return Tree::GenomicInterval->new;
}

#_build_five_prime_Gs
#
#Usage       : $crRNA->_build_five_prime_Gs;
#Purpose     : builder for five_prime_Gs attribute
#               default is 0 unless target sequence has any Gs at the start
#Returns     : Int (EITHER 0, 1 or 2)
#Parameters  : None
#Throws      : 
#Comments    : 

sub _build_five_prime_Gs {
    my ( $self, ) = @_;
    
    my $five_prime_Gs = 0;
    if( $self->target_seq && $self->target_seq =~ m/\AG/xms ){
        $five_prime_Gs = length $1;
    }
    
    return $five_prime_Gs;
}

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 NAME
 
<Crispr> - <Main Module for creating Crispr objects.>

 
=head1 SYNOPSIS
 
    use Crispr::Target;
    my $crispr_design = Crispr->new(
        species => 'zebrafish',
        target_genome => 'target_genome.fa',
        slice_adaptor => $slice_adaptor,
        annotation_file => 'annotation.gff',
        annotation_tree => $tree,
        debug => 0,
    );
    
    # print out target summary or info
    print join("\t", $target->summary ), "\n";
    print join("\t", $target->info ), "\n";
    

=head1 DESCRIPTION
 
Object of this class represent a targets strecth of DNA to search for potential crispr target sites. 
 
=head1 DIAGNOSTICS
 
 
=head1 CONFIGURATION AND ENVIRONMENT
 
 
=head1 DEPENDENCIES
 
 
=head1 INCOMPATIBILITIES
 
