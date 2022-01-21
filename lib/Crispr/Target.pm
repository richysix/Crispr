## no critic (RequireUseStrict, RequireUseWarnings, RequireTidyCode)
package Crispr::Target;

## use critic

# ABSTRACT: Target object - representing a target piece of DNA

use namespace::autoclean;
use Moose;
use Moose::Util::TypeConstraints;
use Crispr::crRNA;
use Carp;
use Scalar::Util qw( weaken );
use DateTime;

with 'Crispr::SharedMethods';

my $debug = 0;

enum 'Crispr::Target::Strand', [qw( 1 -1 )];

subtype 'Crispr::Target::NOT_EMPTY',
    as 'Str',
    where { $_ ne '' },
    message { "Attribute is empty!\n" };

=method new

  Usage       : my $target = Crispr::Target->new(
					target_id => undef,
                    target_name => 'hspa5_exon1',
                    assembly => 'Zv9',
					chr => '5',
					start => 20103030,
					end => 20103930,
					strand => '1',
					species => 'zebrafish',
					requires_enzyme => y,
					gene_id => 'ENSDARG00000004665',
					gene_name => 'hspa5,
					requestor => 'richard.white',
					ensembl_version => 75,
                    status => 'REQUESTED'
					status_changed => '2014-03-02',
                    crRNAs => \@crRNAs,
					target_adaptor => $target_adaptor,
                );
  Purpose     : Constructor for creating target objects
  Returns     : Crispr::Target object
  Parameters  : target_id => Int
                target_name => String
                assembly => String
                chr => String
                start => Int
                end => Int
                strand => '1' or '-1'
                species => String
                requires_enzyme => 1, 0, 'y' or 'n'
                gene_id => String
                gene_name => String
                requestor => String
                ensembl_version => Int
                status_changed => DateTime or String (yyyy-mm-dd)
                crRNAs => ArrayRef of Crispr::crRNA objects
				target_adaptor => Crispr::DB::targetAdaptor,
  Throws      : If parameters are not the correct type
  Comments    : None

=cut

=method target_id

  Usage       : $target->target_id;
  Purpose     : Getter for target_id (database id) attribute
  Returns     : Int (can be undef)
  Parameters  : Int
  Throws      :
  Comments    :

=cut

has 'target_id' => (
    is => 'rw',
    isa => 'Maybe[Int]',
);

=method target_name

  Usage       : $target->target_name;
  Purpose     : Getter for target_name attribute
  Returns     : String
  Parameters  :
  Throws      : If input is given
  Comments    :

=cut

has 'target_name' => (
    is => 'ro',
    isa => 'Crispr::Target::NOT_EMPTY',
);

=method assembly

  Usage       : $target->assembly;
  Purpose     : Getter for assembly attribute
  Returns     : String
  Parameters  :
  Throws      : If input is given
  Comments    :

=cut

has 'assembly' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

=method chr

  Usage       : $target->chr;
  Purpose     : Getter for chr attribute
  Returns     : String
  Parameters  :
  Throws      : If input is given
  Comments    :

=cut

has 'chr' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

=method start

  Usage       : $target->start;
  Purpose     : Getter for start attribute
  Returns     : Int
  Parameters  :
  Throws      : If input is given
  Comments    :

=cut

=method end

  Usage       : $target->end;
  Purpose     : Getter for end attribute
  Returns     : Int
  Parameters  :
  Throws      : If input is given
  Comments    :

=cut

# enforce start < end - NEED TO IMPLEMENT
has [ 'start', 'end' ] => (
    is => 'ro',
    isa => 'Int',
);

=method strand

  Usage       : $target->strand;
  Purpose     : Getter for strand attribute
  Returns     : String
  Parameters  :
  Throws      : If input is given
  Comments    :

=cut

has 'strand' => (
    is => 'ro',
    isa => 'Crispr::Target::Strand',
    default => '1',
);

=method species

  Usage       : $target->species;
  Purpose     : Getter for species attribute
  Returns     : String
  Parameters  :
  Throws      : If input is given
  Comments    :

=cut

has 'species' => (
    is => 'rw',
    isa => 'Maybe[Str]',
);

=method requires_enzyme

  Usage       : $target->requires_enzyme;
  Purpose     : Getter for requires_enzyme attribute
  Returns     : Bool
  Parameters  : Bool    1 for y, 0 for n
  Throws      :
  Comments    :

=cut

has 'requires_enzyme' => (
    is => 'rw',
    isa => 'Bool',
    default => 0,
);

=method gene_id

  Usage       : $target->gene_id;
  Purpose     : Getter for gene_id attribute
  Returns     : String
  Parameters  :
  Throws      : If input is given
  Comments    :

=cut

has 'gene_id' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

=method gene_name

  Usage       : $target->gene_name;
  Purpose     : Getter for gene_name attribute
  Returns     : String
  Parameters  :
  Throws      : If input is given
  Comments    :

=cut

has 'gene_name' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

=method requestor

  Usage       : $target->requestor;
  Purpose     : Getter for requestor attribute
  Returns     : String
  Parameters  :
  Throws      : If input is given
  Comments    :

=cut

has 'requestor' => (
    is => 'ro',
    isa => 'Maybe[Str]',
);

=method ensembl_version

  Usage       : $target->ensembl_version;
  Purpose     : Getter for ensembl_version attribute
  Returns     : String
  Parameters  :
  Throws      : If input is given
  Comments    :

=cut

has 'ensembl_version' => (
    is => 'ro',
    isa => 'Maybe[Int]',
);

=method status

  Usage       : $crRNA->status;
  Purpose     : Setter/Getter for status attribute
  Returns     : Str
  Parameters  : None
  Throws      : If status is not one of the specified ones
  Comments    :

=cut

has 'status' => (
    is => 'rw',
    isa => enum( [ qw{ REQUESTED DESIGNED ORDERED MADE INJECTED
    MISEQ_EMBYRO_SCREENING PASSED_EMBRYO_SCREENING FAILED_EMBRYO_SCREENING
    SPERM_FROZEN MISEQ_SPERM_SCREENING PASSED_SPERM_SCREENING
    FAILED_SPERM_SCREENING SHIPPED SHIPPED_AND_IN_SYSTEM IN_SYSTEM CARRIERS
    F1_FROZEN  } ] ),
#    builder => '_build_status',
    default => 'REQUESTED',
);

=method status_changed

  Usage       : $target->status_changed;
  Purpose     : Getter/Setter for status_changed attribute
  Returns     : DateTime
  Parameters  : Either DateTime object or Str of form yyyy-mm-dd
  Throws      :
  Comments    :

=cut

has 'status_changed' => (
    is => 'rw',
    isa => 'Maybe[DateTime]',
    default => undef,
);

=method crRNAs

  Usage       : $target->crRNAs;
  Purpose     : Getter/Setter for crRNAs attribute
  Returns     : ArrayRef of Crispr::crRNA objects
  Parameters  : ArrayRef of Crispr::crRNA objects
  Throws      :
  Comments    :

=cut

has 'crRNAs' => (
    is => 'rw',
    isa => 'ArrayRef[Crispr::crRNA]',
);

=method target_adaptor

  Usage       : $target->target_adaptor;
  Purpose     : Getter/Setter for target_adaptor attribute
  Returns     : Crispr::DB::TargetAdaptor
  Parameters  : Crispr::DB::TargetAdaptor
  Throws      :
  Comments    :

=cut

has 'target_adaptor' => (
    is => 'rw',
    isa => 'Crispr::DB::TargetAdaptor',
);

around BUILDARGS => sub{
    my $method = shift;
    my $self = shift;
    my %args;

    if( !ref $_[0] ){
        for( my $i = 0; $i < scalar @_; $i += 2){
            my $k = $_[$i];
            my $v = $_[$i+1];
            if( $k eq 'status_changed' ){
                if( defined $v && ( !ref $v || ref $v ne 'DateTime' ) ){
                    my $date_obj = $self->_parse_date( $v );
                    $v = $date_obj;
                }
            }
            elsif( $k eq 'chr' && ( defined $v && $v eq '' ) ){
                $v = undef;
            }
			elsif( $k eq 'strand' && ( $v ne '1' && $v ne '-1' ) ){
				my $strand = $self->_parse_strand_input( $v );
				$v = $strand;
			}
			elsif( $k eq 'requires_enzyme' && ( !defined $v || ( $v ne '1' && $v ne '0' ) ) ){
				my $requires_enzyme = $self->_parse_requires_enzyme_input( $v );
				$v = $requires_enzyme;
			}
			#elsif( $k eq 'crRNAs' ){
			#	foreach my $crRNA_ref ( @{$v} ){
			#		weaken( $crRNA_ref );
			#	}
			#}
            $args{ $k } = $v;
        }
        return $self->$method( \%args );
    }
    elsif( ref $_[0] eq 'HASH' ){
        if( exists $_[0]->{'status_changed'} ){
            if( defined $_[0]->{'status_changed'} &&
                ( !ref $_[0]->{'status_changed'} || ref $_[0]->{'status_changed'} ne 'DateTime' ) ){
                my $date_obj = $self->_parse_date( $_[0]->{'status_changed'} );
                $_[0]->{'status_changed'} = $date_obj;
            }
        }
        if( exists $_[0]->{'chr'} && ( defined $_[0]->{'chr'} && $_[0]->{'chr'} eq '' ) ){
            $_[0]->{'chr'} = undef;
        }
        if( exists $_[0]->{'strand'} && ( $_[0]->{'strand'} ne '1' && $_[0]->{'strand'} ne '-1' ) ){
			my $strand = $self->_parse_strand_input( $_[0]->{'strand'} );
			$_[0]->{'strand'} = $strand;
        }
        if( exists $_[0]->{'requires_enzyme'} &&
            ( !defined $_[0]->{'requires_enzyme'} ||
            ( $_[0]->{'requires_enzyme'} ne '1' &&
                $_[0]->{'requires_enzyme'} ne '0' ) ) ){
			my $requires_enzyme = $self->_parse_requires_enzyme_input( $_[0]->{'requires_enzyme'} );
			$_[0]->{'requires_enzyme'} = $requires_enzyme;
        }
		#if( exists $_[0]->{'crRNAs'} ){
		#	foreach my $crRNA_ref ( @{$_[0]->{'crRNAs'}} ){
		#		weaken( $crRNA_ref );
		#	}
		#}
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
		return;
	}
}

# around requires_enzyme
# This is to convert the underlying Boolean value into either y or n
#
around 'requires_enzyme' => sub {
    my ( $method, $self, $input ) = @_;
    if( defined $input ){
        my $req_enzyme = $self->_parse_requires_enzyme_input($input);
        if( !defined $req_enzyme ){
            warn "The value for $input is not a recognised value. Should be one of 1, 0, y or n.\n";
            return $self->$method();
        }
        return $self->$method( $req_enzyme );
    }
    else{
        my $output = $self->$method();
        if( $output ){
            return 'y';
        }
        else {
            return 'n';
        }
    }
};

## around crRNAs
## This is to weaken references to crRNAs to prevent circular references
#
#around 'crRNAs' => sub {
#    my ( $method, $self, $input ) = @_;
#    if( $input ){
#		foreach my $crRNA ( @{$input} ){
#            if( defined $crRNA->target ){
#                weaken( $crRNA->target );
#            }
#		}
#        return $self->$method( $input );
#    }
#    else{
#		return $self->$method();
#    }
#};

#_parse_requires_enzyme_input
#
#Usage       : $crRNA->_parse_requires_enzyme_input( '+' );
#Purpose     : Accepts either 0, 1, n, and y
#               Converts y to 1 and n to 0.
#               1 and 0 remain unchanged.
#               Anything else is converted to 0.
#               Default value is 1
#Returns     : 1 OR 0
#Parameters  : String
#Throws      :
#Comments    :

sub _parse_requires_enzyme_input {
	my ( $self, $requires_enzyme ) = @_;
    
    my $enzyme;
    if( defined $requires_enzyme ){
        $enzyme = $requires_enzyme eq '1'	    ?	1
            :		$requires_enzyme eq '0'		?	0
            :		$requires_enzyme eq 'y'		?	1
            :		$requires_enzyme eq 'n'		?	0
            :										undef
            ;
    } else {
        $enzyme = undef;
    }
	return $enzyme;
}

=method region

  Usage       : $target->region;
  Purpose     : Getter for region attribute
  Returns     : String ( [CHR:]START-END:STRAND )
  Parameters  : None
  Throws      :
  Comments    :

=cut

sub region {
    my ( $self, ) = @_;

    my $region;
    if( !defined $self->chr ){
        $region = join('-', $self->start, $self->end, ) . ":" . $self->strand;
    }
    else{
        $region = join(':',
            $self->chr,
            join('-',
                $self->start,
                $self->end,
            ),
            $self->strand,
        );
    }
    return $region;
}

=method length

  Usage       : $target->length;
  Purpose     : Returns the length of the target sequence
  Returns     : Int
  Parameters  : None
  Throws      :
  Comments    :

=cut

sub length {
	my ( $self, ) = @_;
	return $self->end - ($self->start - 1);
}

=method summary

  Usage       : $target->summary;
  Purpose     : Returns a short summary of the target info
  Returns     : Array
  Parameters  : None
  Throws      :
  Comments    : undef attributes are replaced with NULL

=cut

sub summary {
    my ( $self, $header, ) = @_;
    my @info = ();
    if ($header) {
        @info = (qw{target_name gene_id gene_name requestor});
    } else {
        @info = ( $self->target_name, );
        push @info, ( $self->gene_id || 'NULL' );
        push @info, ( $self->gene_name || 'NULL' );
        push @info, ( $self->requestor || 'NULL' );
    }

    return @info;
}

=method info

  Usage       : $target->info;
  Purpose     : Returns target info
  Returns     : Array
  Parameters  : None
  Throws      :
  Comments    : undef attributes are replaced with NULL

=cut

sub info {
    my ( $self, $header, ) = @_;
    my @info;

    if ($header) {
        @info = (qw{ target_id target_name assembly chr start end strand
        species requires_enzyme gene_id gene_name requestor ensembl_version });
    } else {
        push @info, ( $self->target_id || 'NULL' );
        push @info,   $self->target_name;
        push @info, ( $self->assembly || 'NULL' );
        push @info, ( $self->chr || 'NULL' );
        push @info,   $self->start;
        push @info,   $self->end;
        push @info,   $self->strand;
        push @info, ( $self->species || 'NULL');
        push @info,   $self->requires_enzyme;
        push @info, ( $self->gene_id || 'NULL');
        push @info, ( $self->gene_name || 'NULL');
        push @info, ( $self->requestor || 'NULL' );
        push @info, ( $self->ensembl_version || 'NULL' );
    #    push @info, ( $self->status_changed || 'NULL' );
    }
    return @info;
}

# around status_changed
# This is to accept either a DateTime object or a string in form yyyy-mm-dd
#
around 'status_changed' => sub {
    my ( $method, $self, $input ) = @_;
    my $date_obj;

    if( $input ){
        #is the input already a DateTime object
        if( ref $input eq 'DateTime' ){
            $date_obj = $input;
        }
        else{
            # parse date info
            $date_obj = $self->_parse_date( $input );
        }
        return $self->$method( $date_obj );
    }
    else{
        if( defined $self->$method ){
            return $self->$method->ymd;
        }
        else{
            return $self->$method;
        }
    }
};

around 'gene_name' => sub {
    my ( $method, $self, $input ) = @_;
    if( $input ){
        return $self->$method( $input );
    }
    else{
        my $gene_name = $self->$method;
        if( defined $gene_name ){
            $gene_name =~ s|[()]||xmsg;
            $gene_name =~ s|\s+|_|xmsg;
        }
        return $gene_name;
    }
};

__PACKAGE__->meta->make_immutable;
1;

__END__

=pod

=head1 SYNOPSIS

    use Crispr::Target;
    my $target = Crispr::Target->new(
        target_name => 'SLC39A14',
        assembly => 'Zv9',
        chr => '5',
        start => 18067321,
        end => 18083466,
        strand => '-1',
        species => 'danio_rerio',
        requires_enzyme => y,
        gene_id => 'ENSDARG00000090174',
        gene_name => 'SLC39A14',
        requestor => 'richard.white',
        ensembl_version => 75,
        status => 'PASSED_EMBRYO_SCREENING'
        status_changed => '2014-03-02',
    );

    # print out target summary or info
    print join("\t", $target->summary ), "\n";
    print join("\t", $target->info ), "\n";


=head1 DESCRIPTION

Object of this class represent a target stretch of DNA to search for potential crispr target sites.

=head1 DIAGNOSTICS


=head1 CONFIGURATION AND ENVIRONMENT


=head1 DEPENDENCIES


=head1 INCOMPATIBILITIES
