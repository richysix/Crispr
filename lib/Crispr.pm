## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr;
## use critic

# ABSTRACT: Crispr - used for designing crispr guide RNAs

use warnings;
use strict;
use autodie qw(:all);
use List::MoreUtils qw( any );
use Carp;
use English qw( -no_match_vars );
use File::Which;

use Moose;
use Moose::Util::TypeConstraints;
use namespace::autoclean;
use Crispr::crRNA;
use Crispr::Target;
use Crispr::OffTarget;
use Crispr::OffTargetInfo;

use Tree::AnnotationTree;
use Tree::GenomicIntervalTree;

use Bio::Seq;
use Bio::SeqIO;
use Bio::DB::Fasta;

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
                annotation_tree => Tree::AnnotationTree,
                off_targets_interval_tree => Tree::GenomicIntervalTree,
                debug => Int,
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method target_seq

  Usage       : $crispr_design->target_seq;
  Purpose     : Getter for target_seq attribute
  Returns     : Str (must be a valid DNA string)
  Parameters  : None
  Throws      : If input is given when called after object construction
                If the attribute contains characters not in this set: ACGTNRYSWMKBDHV
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
  Throws      : If input is given when called after object construction
                If the attribute contains characters not in this set: ACGTNRYSWMKBDHV
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
  Throws      : If input is given when called after object construction
                If attribute is anything other than 0, 1 OR 2
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
  Throws      : If input is given when called after object construction
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
  Throws      : If input is given when called after object construction.
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
  Throws      : If input is given when called after object construction
                If attribute is not a Bio::EnsEMBL::DBSQL::SliceAdaptor object
  Comments    : 

=cut

has 'slice_adaptor' => (
    is => 'ro',
    isa => 'Bio::EnsEMBL::DBSQL::SliceAdaptor',
);

=method targets

  Usage       : $crispr_design->targets;
  Purpose     : Getter for targets attribute
  Returns     : ArrayRef of Crispr::Target objects
  Parameters  : None
  Throws      : If input is given when called after object construction
  Comments    : 

=cut

has 'targets' => (
    is => 'ro',
    isa => 'ArrayRef[Crispr::Target]',
    writer => '_set_targets',
);

=method all_crisprs

  Usage       : $crispr_design->all_crisprs;
  Purpose     : Getter for all_crisprs attribute
  Returns     : HashRef
  Parameters  : None
  Throws      : If input is given when called after object construction
  Comments    : Hash keys are crRNA_name '_' Target_name

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
  Throws      : If input is given when called after object construction
                If file does not exist or is empty.
  Comments    : 

=cut

has 'annotation_file' => (
    is => 'ro',
    isa => 'Crispr::FileExists',
);

=method annotation_tree

  Usage       : $crispr_design->annotation_tree;
  Purpose     : Getter for annotation_tree attribute
  Returns     : Tree::AnnotationTree
  Parameters  : None
  Throws      : If input is given when called after object construction
  Comments    : 

=cut

has 'annotation_tree' => (
    is => 'ro',
    isa => 'Tree::AnnotationTree',
    builder => '_build_annotation_tree',
    lazy => 1,
);

=method off_targets_interval_tree

  Usage       : $crispr_design->off_targets_interval_tree;
  Purpose     : Getter for off_targets_interval_tree attribute
  Returns     : Set::GenomicTree
  Parameters  : None
  Throws      : If input is given when called after object construction
  Comments    : 

=cut

has 'off_targets_interval_tree' => (
    is => 'ro',
    isa => 'Tree::GenomicIntervalTree',
    builder => '_build_interval_tree',
    lazy => 1,
);

=method debug

  Usage       : $crispr_design->debug;
  Purpose     : Getter for debug attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given when called after object construction
  Comments    : 

=cut

has 'debug' => (
    is => 'ro',
    isa => 'Int',
);

#_testing
#
#Usage       : $crRNA->_testing;
#Purpose     : Internal method for to indicate whether testing is being done.
#Returns     : value for $testing
#Parameters  : value to set $testing to  => Int
#Throws      : 
#Comments    : If testing is set it alters the behaviour of the off-target methods

my $testing;
sub _testing {
    my $self = shift @_;
    $testing = shift @_;
}

#_seen_crRNA_id
#
#Usage       : $crRNA->_seen_crRNA_id;
#Purpose     : Internal method for checking if a particular crRNA has been seen before
#Returns     : 1 if crRNA has been seen before, 0 otherwise
#Parameters  : crRNA name
#              Target name
#Throws      : 
#Comments    : 

# This hash is used to keep track of crRNAs for every target
# keys are concatenated crRNA name and Target name
my $crRNA_seen = {};
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

# This hash is used to keep track of every target name
# keys are Target names
my $target_seen = {};
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
		croak "A region must be supplied to find_crRNAs_by_region!\n";
	}
	if( !defined $self->target_seq ){
		croak "The target_seq attribute must be defined to search for crRNAs!\n";
	}
    # get target name. If no target, use region as name.
    my $target_name = defined $target   ?   $target->target_name   :   $region;
    
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
		croak "Couldn't understand region - $region.\n";
	}
	my ( $start, $end ) = split /-/, $interval;
	if( !$start || !$end ){
		croak "Couldn't understand region - $region.\n";
	}
    
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
        A => '[A]',
        C => '[C]',
        G => '[G]',
        T => '[T]',
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
			croak "Base, ", $_, " is not an accepted IUPAC code.\n";
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
                If the target's region cannot be understood by find_crRNAs_by_region
  Comments    : Only crRNAs with cut-sites inside the target region are retained

=cut

sub find_crRNAs_by_target {
	my ( $self, $target, ) = @_;
	if( !defined $target ){
		croak "A Crispr::Target must be supplied to find_crRNAs_by_target!\n";
	}
    if( !$target->isa('Crispr::Target') ){
        croak "A Crispr::Target object is required for find_crRNAs_by_target",
            "not a ", ref $target, ".\n";
    }
	if( $self->_seen_target_name( $target->target_name ) ){
		croak "This target, ", $target->target_name,", has been seen before.\n";
	}
	my $crRNAs;
    eval {
        $crRNAs = $self->find_crRNAs_by_region( $target->region, $target );
    };
    if( $EVAL_ERROR ){
        if( $EVAL_ERROR =~ m/A\sregion\smust\sbe\ssupplied/xms ){
            croak join("\n", 'This target does not have an associated region!',
                'The attributes chr, start and end need to be set when the target object is created for find_crRNAs_by_target to work.',
            ), "\n";
        }
        elsif( $EVAL_ERROR =~ m/Couldn't\sunderstand\sregion/xms ){
            croak join("\n", "Couldn't understand the target's region!",
                join(q{ }, 'Target:', $target->target_name,),
                join(q{ }, 'Region:', $target->region,), ), "\n";
        }
        else{
            croak $EVAL_ERROR;
        }
    }
    
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
        croak "The supplied argument is not an ArrayRef!\n";
    }
    foreach ( @{$targets} ){
        if( !ref $_ || !$_->isa('Crispr::Target') ){
            croak "One of the supplied objects is not a Crispr::Target object, it's a ",
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
		croak "The supplied object is not a Crispr::Target object, it's a ",
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
		croak "The supplied object is not a Crispr::Target object, it's a ",
                ref $target, ".\n";
	}
	my @targets_to_keep = grep { $_->target_name ne $target->target_name } @{$self->targets};
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
        croak "The supplied argument is neither an ArrayRef or a HashRef!\n";
    }
	if( ref $crRNAs eq 'ARRAY' ){
		foreach ( @{$crRNAs} ){
			if( !ref $_ || !$_->isa('Crispr::crRNA') ){
				croak "One of the supplied objects is not a Crispr::crRNA object, it's a ",
					ref $_, ".\n";
			}
		}
		
		# check all crRNAs have a target
		if( !$target_name && any { !defined $_->target } @{$crRNAs} ){
			croak "Method: add_crisprs - Each crRNA must have an associated target or a target name must be supplied for all supplied crRNAs!\n";
		}
		my $crispr_ref = $self->all_crisprs;
		$crispr_ref = {} if( !defined $crispr_ref );
		foreach my $crRNA ( @{$crRNAs} ){
            $target_name = !$target_name    ?   $crRNA->target->target_name
                :                               $target_name;
			$crispr_ref->{$crRNA->name . q{_} . $target_name} = $crRNA;
		}
		$self->_set_all_crisprs( $crispr_ref );
	}
	elsif( ref $crRNAs eq 'HASH' ){
		foreach ( keys %{$crRNAs} ){
			if( !ref $crRNAs->{$_} || !$crRNAs->{$_}->isa('Crispr::crRNA') ){
				croak "One of the supplied objects is not a Crispr::crRNA object, it's a ",
					ref $crRNAs->{$_}, ".\n";
			}
		}
		
		# check all crRNAs have a target
		if( !$target_name && any { !defined $crRNAs->{$_}->target } keys %{$crRNAs} ){
			croak "Method: add_crisprs - Each crRNA must have an associated target or a target name must be supplied for all supplied crRNAs!\n";
		}
		my $crispr_ref = $self->all_crisprs;
		$crispr_ref = {} if( !defined $crispr_ref );
		foreach my $crRNA_name ( keys %{$crRNAs} ){
            my $crRNA = $crRNAs->{$crRNA_name};
            $target_name = !$target_name    ?   $crRNA->target->target_name
                :                               $target_name;
			$crispr_ref->{$crRNA_name . q{_} . $target_name} = $crRNA;
		}
		$self->_set_all_crisprs( $crispr_ref );
	}
	else{
        croak "The supplied argument is neither an ArrayRef or a HashRef!\n";
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
        croak "The supplied argument is neither an ArrayRef or a HashRef!\n";
    }
	if( ref $crRNAs eq 'ARRAY' ){
		foreach ( @{$crRNAs} ){
			if( !ref $_ || !$_->isa('Crispr::crRNA') ){
				croak "One of the supplied objects is not a Crispr::crRNA object, it's a ",
					ref $_, ".\n";
			}
		}
		
		# check all crRNAs have a target
		if( any { !defined $_->target } @{$crRNAs} ){
			croak "Each crRNA must have an associated target!\n";
		}
		my $crispr_ref = $self->all_crisprs;
		$crispr_ref = {} if( !defined $crispr_ref );
		foreach my $crRNA ( @{$crRNAs} ){
			delete $crispr_ref->{$crRNA->name . q{_} . $crRNA->target->target_name};
		}
		$self->_set_all_crisprs( $crispr_ref );
	}
	elsif( ref $crRNAs eq 'HASH' ){
		foreach ( keys %{$crRNAs} ){
			if( !ref $_ || !$_->isa('Crispr::crRNA') ){
				croak "One of the supplied objects is not a Crispr::crRNA object, it's a ",
					ref $_, ".\n";
			}
		}
		
		# check all crRNAs have a target
		if( any { !defined $crRNAs->{$_}->target } keys %{$crRNAs} ){
			croak "Each crRNA must have an associated target!\n";
		}
		my $crispr_ref = $self->all_crisprs;
		$crispr_ref = {} if( !defined $crispr_ref );
		foreach my $crRNA_name ( keys %{$crRNAs} ){
            my $crRNA = $crRNAs->{$crRNA_name};
			delete $crispr_ref->{$crRNA_name . q{_} . $crRNA->target->target_name};
		}
		$self->_set_all_crisprs( $crispr_ref );
	}
	else{
        croak "The supplied argument is neither an ArrayRef or a HashRef!\n";
	}
}

=method target_seq_length

  Usage       : $crRNA->_build_target_seq_length;
  Purpose     : Getter for target_seq_length attribute
  Returns     : Int
  Parameters  : None
  Throws      : If input is given when called after object construction
  Comments    : 

=cut

my $target_seq_length;
sub target_seq_length {
    my ( $self, $input, ) = @_;
    
    if( $input ){
        croak "target_seq_length is a read-only attribute. It cannot be set.\n";
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
  Comments    : method attempts to fetch sequence for the crRNA if there is a
                connection to the Ensembl db or from a reference fasta file.
                If no sequence can be retrieved it is left undefined.

=cut

sub create_crRNA_from_crRNA_name {
    my ( $self, $name, $species, ) = @_;
    
    my ( $chr, $start, $end, $strand ) = $self->parse_cr_name( $name );
    
    my %args = (
        chr => $chr,
        start => $start,
        end => $end,
        strand => $strand || 1,
        species => $species || undef,
    );
    
    # get sequence if possible
    my $sequence;
    my $seq_obj = $self->_fetch_sequence( $chr, $start, $end, $strand, );
    if( !$seq_obj ){
        warn "Couldn't retrieve sequence for crRNA: $name. Continuing without it...\n";
    }
    else{
        $sequence = $seq_obj->seq;
    }
    if( defined $sequence ){
        $args{sequence} = $sequence;
    }
    
    my $crRNA = Crispr::crRNA->new( \%args );
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
        croak "Could not understand crRNA name. Should at least be crRNA:CHR:START-END.\n";
    }
    my ( $start, $end ) = split /-/, $range;
    
    return ( $chr, $start, $end, $strand );
}

=method find_off_targets

  Usage       : $crispr->find_off_targets( $crRNAs, $basename, );
  Purpose     : Searches for potential off-target hits for crRNAs using bwa
  Returns     : ArrayRef of Crispr::crRNA objects
  Parameters  : ArrayRef of Crispr::crRNA objects
                Basename for tmp output files   (String)
  Throws      : 
  Comments    : Basename set to tmp if undefined

=cut

sub find_off_targets {
    my ( $self, $crRNAs, $basename, ) = @_;
    
    # check whether bwa is installed in the current PATH
    my $bwa_path = which( 'bwa' );
    if( !$bwa_path ){
        croak join("\n", 'Could not find bwa installed in the current path!',
            'Either install bwa in the current path or alter the path to include the bwa directory', ), "\n";
    }
    
    $basename = $basename  ?   $basename    :   'tmp';
    $self->output_fastq_for_off_targets( $crRNAs, $basename, );
    $self->bwa_align( $basename, );
    $self->filter_and_score_off_targets( $crRNAs, $basename, );
    return $crRNAs;
}

=method output_fastq_for_off_targets

  Usage       : $crispr->output_fastq_for_off_targets( $crRNAs, $basename, );
  Purpose     : Outputs a fastq file for off-target checking by bwa
  Returns     : 1 on Success
  Parameters  : ArrayRef of Crispr::crRNA objects
                Basename for tmp output files   (String)
  Throws      : If output FASTQ file cannot be opened
  Comments    : 

=cut

sub output_fastq_for_off_targets {
    my ( $self, $crRNAs, $basename, ) = @_;
	
    my $crispr_fq_filename = $basename . '.fq';
    open my $fq_fh, '>', $crispr_fq_filename or croak join("\n",
        "Scoring off-targets failed!",
        "Couldn't open file, $crispr_fq_filename",
        $OS_ERROR, ), "\n";
    
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
  Comments    : bwa must be installed in the user's path

=cut

sub bwa_align {
	my ( $self, $basename, ) = @_;
	my $fq_filename = $basename . '.fq';
	my $sai_filename = $basename . '.sai';
	#my $align_cmd = join(q{ }, 'bwa aln -n 6 -o 0 -l 20 -k 5 -N',
	#	$self->target_genome, $fq_filename, '>', $sai_filename, );
	my $align_cmd = join(q{ }, 'bwa aln -n 4 -o 0 -l 20 -k 3 -N',
		$self->target_genome, $fq_filename, '>', $sai_filename, );
    $align_cmd .= ' 2> /dev/null' if $testing;
	system( $align_cmd );
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
    
	my $sam_cmd = join(q{ }, 'bwa samse -n 900000',
		$self->target_genome, "$basename.sai", "$basename.fq", );
    $sam_cmd .= ' 2> /dev/null' if $testing;
    
    open (my $sam_pipe, '-|', $sam_cmd) || croak join("\n",
        "Scoring off-targets failed!", $sam_cmd, $OS_ERROR, ), "\n";
    my $line;
    while ( $line = <$sam_pipe>) {
        next if( $line =~ m/\A \@/xms );
		chomp $line;
		my ( $crispr_id, $flag, $chr, $start, $mapq, $cigar_str,
                undef, undef, undef, $seq, undef, @tags, ) = split /\t/, $line;
		next if( !exists $crRNAs->{$crispr_id} );
        
        # parse top hit
        my $strand = $flag == 0         ?	'1'
            :           $flag == 16     ?	'-1'
			:								'1';
        
        my $end = $start - 1 + length( $seq );
        my @mismatches = grep { m/\A NM:i:/xms } @tags;
        $mismatches[0] =~ s/NM:i://xms;
        $self->score_off_targets_from_sam_output( $crRNAs, $crispr_id, $chr,
                                                 $start, $end, $strand, $mismatches[0], );
        
        my @supp_alignments = grep { m/\A XA:Z:/xms } @tags;
        foreach my $supp_align ( map { my $align = $_;
                                        $align =~ s/\A XA:Z://xms;
                                        split /;/, $align; } @supp_alignments ){
            next if( $supp_align eq q{} );
            my ( $chr, $pos, $cigar, $mismatch ) = split /,/, $supp_align;
            my $strand = substr($pos, 0, 1, "");
            $strand = $strand eq '+'    ?   '1'
                :       $strand eq '-'  ?   '-1'
                :                           '1';
            my $end = $pos - 1 + length( $seq );
            
            #get slice
            #my $off_target_slice = $self->slice_adaptor->fetch_by_region( 'toplevel', $chr, $pos, $end, $strand, );
            my $off_target_slice = $self->_fetch_sequence( $chr, $pos, $end, $strand, );
            next if( $off_target_slice->seq !~ m/GG\z/xms || $off_target_slice->seq =~ m/N/xms );
            warn $crRNAs->{$crispr_id}->name, "\t", $off_target_slice->seq, "\t", $off_target_slice->strand, "\n" if( $self->debug == 2 );
            $crRNAs = $self->score_off_targets_from_sam_output( $crRNAs, $crispr_id, $chr, $pos, $end, $strand, $mismatch, );
        }
	}
	return $crRNAs;
}

=method score_off_targets_from_sam_output

  Usage       : $crispr->score_off_targets_from_sam_output( $crRNAs, $id, $chr, $start, $end, $strand, );
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

sub score_off_targets_from_sam_output {
	my ( $self, $crRNAs, $id, $chr, $start, $end, $strand, $mismatch, ) = @_;
	
	return $crRNAs if( !exists $crRNAs->{$id} );
	my $crRNA = $crRNAs->{$id};
	
	if( !defined $crRNA->off_target_hits ){
		$crRNA->off_target_hits( Crispr::OffTargetInfo->new() );
	}
	#return $crRNAs if( $crRNA->off_target_hits->score < 0.001 );
	return $crRNAs if( defined $crRNA->chr && $crRNA->chr eq $chr && $crRNA->start == $start && $crRNA->end == $end );
	
	# check annotation
	my $annotations = $self->annotation_tree->fetch_overlapping_annotations( $chr, $start, $end );
    my $type;
	if( !@{$annotations} ){
		$type = 'nongenic';
	}
	elsif( any { $_ eq 'exon' } @{$annotations} ){
		$type = 'exon';
	}
	elsif( any { $_ eq 'intron' } @{$annotations} ){
		$type = 'intron';
	}

	# make an off target object and add it to interval tree
	my $off_target_obj = Crispr::OffTarget->new(
		crRNA_name => $id,
		chr => $chr,
		start => $start,
		end => $end,
		strand => $strand,
        mismatches => $mismatch,
        annotation => $type,
	);
	
	$self->off_targets_interval_tree->insert_interval_into_tree( $chr, $start, $end, $off_target_obj );
    $crRNA->off_target_hits->add_off_target( $off_target_obj );
    
	return $crRNAs;
}

=method _fetch_sequence

  Usage       : $crispr->_fetch_sequence( $chr, $pos, $end, $strand, );
  Purpose     : Retrieves sequence for the supplied region using either the Ensembl database or by access the genome fasta file
  Returns     : Either BioSeq or Bio::EnsEMBL::Slice
  Parameters  : Str     chr
                Str     start
                Str     end
                Str     strand
  Throws      : If cannot retrieve the sequence
  Comments    : 

=cut

sub _fetch_sequence {
    my ( $self, $chr, $pos, $end, $strand, ) = @_;
    
    # try Ensembl db first
    my $off_target_slice;
    if( defined $self->slice_adaptor ){
        $off_target_slice = $self->slice_adaptor->fetch_by_region( 'toplevel', $chr, $pos, $end, $strand, );
    }

    # if slice is undef, try fasta file
    if( !defined $off_target_slice && defined $self->target_genome ){
        my $db = Bio::DB::Fasta->new( $self->target_genome );
        my $obj = $db->get_Seq_by_id($chr);
        my $seq = $obj->seq;
        my $subseq = $obj->subseq( $pos => $end );
        $off_target_slice = $strand eq '-1' ?   $subseq->revcom :   $subseq;
    }
    return $off_target_slice;
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

sub calculate_all_pc_coding_scores {
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
        croak "Cannot make an AnnotationTree without an annotation file!\n";
    }
    elsif( $self->annotation_file !~ m/\.gff\z/xms ){
        croak "The annotation file, ", $self->annotation_file, ", doesn't appear to be a gff file!\n";
    }
    elsif( !-e $self->annotation_file || -z $self->annotation_file ){
        croak "The annotation file for exon/intron annotation does not exist or is empty.\n";
    }
    else{
        # assume annotation is in gff format
        $tree = Tree::AnnotationTree->new();
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
    return Tree::GenomicIntervalTree->new;
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

=head1 SYNOPSIS
 
    use Crispr;
    my $crispr_design = Crispr->new(
        species => 'zebrafish',
        target_seq => 'NNNNNNNNNNNNNNNNNNNNNGG',
        PAM => 'NGG',
        five_prime_Gs => 0,
        target_genome => 'target_genome.fa',
        slice_adaptor => $slice_adaptor,
        annotation_file => 'annotation.gff',
        debug => 0,
    );
    
    # find CRISPR target sites (crRNAs) using Crispr::Target objects
    $crRNAs = $crispr_design->find_crRNAs_by_target( $target );
    
    # get targets
    $targets = $crispr_design->targets();
    
    # get a hash of all the crRNAs (keys are 'target_name'_'crRNA_name', values are crRNA objects )
    $crRNAs = $crispr_design->all_crisprs();
    
    # keep crRNAs only on one strand
    $crRNAs = $crispr_design->filter_crRNAs_from_target_by_strand( $target, $strand_to_keep );

    # keep the top scoring crRNAs
    $crRNAs = $crispr_design->filter_crRNAs_from_target_by_score( $target, $number_to_keep );

    # add or remove target(s) to crispr_design object
    $crispr_design->add_target( $target );
    $crispr_design->add_targets( \@targets );
    $crispr_design->remove_target( $target );
    
    # add or remove crRNAs
    $crispr_design->add_crisprs( \@crRNAs );
    $crispr_design->remove_crisprs( \@crRNAs );

    
    $target_length = $crispr_design->target_seq_length();
    
    # use a crRNA id
    $crRNA = $crispr_design->create_crRNA_from_crRNA_name( 'crRNA:5:123-145:1' );
    ( $chr, $start, $end, $strand ) = $crispr_design->parse_cr_name( $crRNA->name );
    
    # calculate potential off target sites for targets
    $crispr_design->find_off_targets( $crispr_design->all_crisprs );
    
    # calculate protein-coding scores
    $crispr_design->calculate_all_pc_coding_scores( $crRNA, $transcripts );
    
    
=head1 DESCRIPTION
 
Objects of this class implement methods to find and score CRISPR target sites.
It uses the other Crispr Modules to do this.

=over

=item B<Crispr::Target>

This object represents a stretch of DNA that is to be searched for possible
CRISPR target sites. It can correspond to an exon, transcript or gene, but it
can also be any arbitrary region in a genome.

=item B<Crispr::crRNA>

This object represents a single CRISPR target site.

=item B<Crispr::OffTarget>

This object is used to hold the positions of potential off-target sites for a
CRISPR target.

=item B<Crispr::EnzymeInfo>

This object is used to hold information about restriction enzymes that cut
amplicons that are used to screen the efficiency of CRISPR guide RNAs.
Note: Currently can be added as an attribute to a crRNA object, but may be
better done as an attribute of a PrimerPair.

=item B<Crispr::CrisprPair>

This object represents two CRISPR target sites to be used as a pair to produce
a specific deletion. It is comprised of two crRNA objects and two Target
objects which can be the same region. The first crRNA of the pair must be on
the reverse strand and the second on the forward strand. This orientation has
been shown to be more efficient at inducing indels than the opposite one
(http://dx.doi.org/10.1016/j.cell.2013.08.021).

=item B<Crispr::PrimerDesign>

This object is used to design PCR primers for screening the efficiency of
specific CRISPR guide RNAs

=item B<Crispr::Config>

A helper object for importing and parsing config files.

=back

=head1 DIAGNOSTICS

=over

=item Not a valid crRNA target sequence

The supplied sequence must only contain the characters ACGTNRYSWMKBDHV.

=item File does not exist or is empty.

If the target_genome attribute is supplied to the C<new> method it must exist and not be empty.

=item A region must be supplied to find_crRNAs_by_region

This means that the attribute target_seq was not defined when the Crispr object was created with a call to C<new>.
The C<find_crRNAs> methods cannot work if no target sequence is defined.

=item The target_seq attribute must be defined to search for crRNAs

This means that the attribute target_seq was not defined when the Crispr object was created with a call to C<new>.
The C<find_crRNAs> methods cannot work if no target sequence is defined.

=item Couldn't understand region

This means that the C<find_crRNAs_by_region> method could not correctly parse the region supplied.
The region must be in the format CHR:START-END[:STRAND] (Strand defaults to '1').

=item Base, is not an accepted IUPAC code.

The target sequence must only be composed of the characters ACGTNRYSWMKBDHV.
This should be checked on the creation of the Crispr object so this error message should never be encountered!

=item A Crispr::Target must be supplied to find_crRNAs_by_target

This means that C<find_crRNAs_by_target> was called without a defined Crispr::Target object.

=item A Crispr::Target object is required for find_crRNAs_by_target

This means that C<find_crRNAs_by_target> was called with an object that is not a Crispr::Target object.

=item This target, ", $target->target_name,", has been seen before.

This means that the name of the Crispr::Target supplied to C<find_crRNAs_by_target> has been seen before.
A Crispr object keeps a record of the targets that it has found crRNAs for so that duplicate crRNAs found in the all_crisprs attribute.
Unfortunately this error is very likely to occur if searching for crRNAs for a gene and so the exception needs to be caught and dealt with.
The scripts supplied with Crispr do this and print a warning saying that the target has been seen before and that it is being skipped.

=item This target does not have an associated region

This means that the Crispr::Target object supplied to C<find_crRNAs_by_target> does not have a defined region.
The chr, start and end attributes of the target must be defined for there to be a defined region.

=item The supplied argument is not an ArrayRef!

The argument supplied to C<add_targets> must be an ArrayRef of Crispr::Target objects

=item One of the supplied objects is not a Crispr::Target object, it's a 

The argument supplied to C<add_targets> must be an ArrayRef of Crispr::Target objects

=item The supplied object is not a Crispr::Target object

The argument supplied to C<add_target/remove_target> must be a Crispr::Target object

=item The supplied argument is neither an ArrayRef or a HashRef!

The argument supplied to C<add_targets/remove_targets> must be either an ArrayRef or a HashRef of Crispr::crRNA objects

=item One of the supplied objects is not a Crispr::crRNA object

All of the objects supplied to C<add_targets/remove_targets> must be Crispr::crRNA objects

=item Method: add_crisprs - Each crRNA must have an associated target or a target name must be supplied for all supplied crRNAs

This means one of the objects supplied to add_crisprs does not have an associated Crispr::Target object.
The Crispr module keeps track of crRNAs by using the crRNA_name and target_name so it needs a target name.
If the target name is the same for all crRNAs it can be supplied as the second argument to the method.

=item Each crRNA must have an associated target!

This means one of the objects supplied to add_crisprs does not have an associated Crispr::Target object.
The Crispr module keeps track of crRNAs by using the crRNA_name and target_name so it needs a target name to remove it.

=item target_seq_length is a read-only attribute. It cannot be set.

The target sequence length attribute cannot be set by the user. It is calculated using the target_seq attribute

=item Could not understand crRNA name. Should at least be crRNA:CHR:START-END.

The format of the crRNA name supplied to C<create_crRNA_from_crRNA_name/parse_cr_name> must be crRNA:CHR:START-END[:STRAND].
The default value for strand is '1'.

=item Scoring off-targets failed

This indicates that something went wrong with the off-target scoring process.
This could be for a few reasons.

=over

=item 1. The FASTQ file for the crRNA target sequence to be tested could not be created.

=item 2. The mapping staged failed

=item 3. The parsing of the results failed

=back

=item Cannot make an AnnotationTree without an annotation file!

This error message occurs if off-target scoring is being done but no annotation file has been supplied by setting the annotation_file attribute.

=item The annotation file, annotation_file_name, doesn't appear to be a gff file!

This error message occurs if off-target scoring is being done and the annotation file is not in gff format.

=item The annotation file for exon/intron annotation does not exist or is empty.

This error message occurs if off-target scoring is being done and the annotation file does not or is empty.

=back
 
=head1 CONFIGURATION AND ENVIRONMENT

bwa (bio-bwa.sourceforge.net) must be installed in the current path for off-target scoring to work.
Also the target genome must have already been indexed by bwa.

Off-target checking uses an Interval Tree for fast checking of annotation.
This needs a file of annotation for species in question in gff format.

## In future, I would like to implement checking of annotation using Ensembl
although this will be probably be considerably slower  ##

All off-targets are also stored in an Interval tree for fast checking of off-target sites that are close together.

=head1 DEPENDENCIES
 
 Set::Interval
 
=head1 INCOMPATIBILITIES
 
