#!/usr/bin/env perl

# PODNAME: add_crispr_pairs_to_db_from_file.pl
# ABSTRACT: Add crRNAs as pairs into CRISPR SQL database.

use warnings; use strict;
use Getopt::Long;
use English qw( -no_match_vars );
use Pod::Usage;
use Data::Dumper;
use DateTime;
use List::MoreUtils qw( any none );
use Bio::EnsEMBL::Registry;

use Crispr;
use Crispr::crRNA;
use Crispr::CrisprPair;
use Crispr::OffTargetInfo;
use Crispr::OffTarget;
use Crispr::DB::DBConnection;
use Crispr::DB::crRNAAdaptor;
use Crispr::Plate;
use Labware::Well;

my %options;
get_and_check_options();

my $comment_regex = qr/#/;

# check registry file and connect to Ensembl db
if( $options{registry_file} ){
    Bio::EnsEMBL::Registry->load_all( $options{registry_file} );
}
else{
    # if no registry file connect anonymously to the public server
    Bio::EnsEMBL::Registry->load_registry_from_db(
      -host    => 'ensembldb.ensembl.org',
      -user    => 'anonymous',
      -port    => 5306,
    );
}

my $ensembl_version = Bio::EnsEMBL::ApiVersion::software_version();
warn "Ensembl version: e", $ensembl_version, "\n" if $options{debug};
print "Ensembl version: e", $ensembl_version, "\n" if $options{verbose};

# Ensure database connection isn't lost; Ensembl 64+ can do this more elegantly
## no critic (ProhibitMagicNumbers)
if ( $ensembl_version < 64 ) {
## use critic
    Bio::EnsEMBL::Registry->set_disconnect_when_inactive();
}
else {
    Bio::EnsEMBL::Registry->set_reconnect_when_lost();
}

# get adaptors
my $slice_adaptor = Bio::EnsEMBL::Registry->get_adaptor( $options{species}, 'core', 'slice' );

# make design object
my $crispr_design = Crispr->new(
    species => $options{species},
    target_genome => $options{target_genome},
    scored => 0,
    slice_adaptor => $slice_adaptor,
    debug => $options{debug},
);

# connect to db
my $db_connection = Crispr::DB::DBConnection->new( $options{crispr_db}, );

# get Target Adaptor using database adaptor
my $target_adaptor = $db_connection->get_adaptor( 'target' );
my $crRNA_adaptor = $db_connection->get_adaptor( 'crRNA' );
my $crispr_pair_adaptor = $db_connection->get_adaptor( 'crispr_pair' );
my $plate_adaptor = $db_connection->get_adaptor( 'plate' );

my @crispr_pair_attributes = ( qw{ pair_name number_paired_off_target_hits
    combined_score deletion_size 
    target_1_name target_1_species target_1_requestor 
    crRNA_1_name crRNA_1_chr crRNA_1_start crRNA_1_end crRNA_1_strand
    crRNA_1_score crRNA_1_sequence crRNA_1_oligo1 crRNA_1_oligo2
    crRNA_1_off_target_score crRNA_1_off_target_counts crRNA_1_off_target_hits
    crRNA_1_coding_score crRNA_1_coding_scores_by_transcript
    crRNA_1_five_prime_Gs crRNA_1_plasmid_backbone crRNA_1_GC_content
    target_2_name target_2_species target_2_requestor 
    crRNA_2_name crRNA_2_chr crRNA_2_start crRNA_2_end crRNA_2_strand
    crRNA_2_score crRNA_2_sequence crRNA_2_oligo1 crRNA_2_oligo2
    crRNA_2_off_target_score crRNA_2_off_target_counts crRNA_2_off_target_hits
    crRNA_2_coding_score crRNA_2_coding_scores_by_transcript
    crRNA_2_five_prime_Gs crRNA_2_plasmid_backbone crRNA_2_GC_content }
);

my @required_attributes1 = ( qw{ pair_name number_paired_off_target_hits
    target_1_name target_1_requestor
    crRNA_1_name crRNA_2_name } );

my @required_attributes2 = ( qw{ pair_name number_paired_off_target_hits
    target_1_name target_1_requestor
    crRNA_1_start crRNA_1_end crRNA_1_sequence
    crRNA_2_start crRNA_2_end crRNA_2_sequence } );

my @columns;
my @crispr_pairs;
my %crRNA_already_exists_in_db;
my $all_in_db = 1;

while(<>){
    my @values;
    
    chomp;
    if( $INPUT_LINE_NUMBER == 1 ){
        if( !m/\A $comment_regex/xms ){
            die "Input needs a header line starting with a #\n";
        }
        s|$comment_regex||xms;
        @columns = split /\t/, $_;
        foreach my $column_name ( @columns ){
            if( none { $column_name eq $_ } @crispr_pair_attributes ){
                die "Could not recognise column name, ", $column_name, ".\n";
            }
        }
        # check for required attributes. 2 different sets so can use either name or start/end
        foreach my $attribute ( @required_attributes1 ){
            if( none { $attribute eq $_ } @columns ){
                # check whether required_attributes2 list is present
                foreach my $attribute2 ( @required_attributes2 ){
                    if( none { $attribute2 eq $_ } @columns ){
                        die "Missing required attribute: ", $attribute, ".\n";
                    }
                }
            }
        }
        next;
    }
    else{
        @values = split /\t/, $_;
    }
    
    my %args;
    for( my $i = 0; $i < scalar @columns; $i++ ){
        if( $values[$i] eq 'NULL' ){
            $values[$i] = undef;
        }
        $args{ $columns[$i] } = $values[$i];
    }
    
    if( $options{debug} == 2 ){
        warn Dumper( %args );
    }
    
    if( !$args{'target_1_name'} || !$args{'target_1_requestor'} ){
        die "Must have a target name and a requestor for each crRNA to add to database.\n",
            $_, "\n";
    }
    if( !$args{'target_2_name'} || !$args{'target_2_requestor'} ){
        warn join("\n", "No values for target_2_name or target_2_requestor.",
                "Using target_1 info for crRNA_2 as well.",
                $_,
            ), "\n";
        $args{'target_2_name'} = $args{'target_1_name'};
        $args{'target_2_requestor'} = $args{'target_1_requestor'}
    }
    # fetch target from db
    ##  need to catch exceptions  ##
    my @targets;
    $targets[1] = $target_adaptor->fetch_by_name_and_requestor( $args{'target_1_name'}, $args{'target_1_requestor'}, );
    $targets[1]->designed( $options{designed} );
    
    $targets[2] = $args{'target_2_name'} . $args{'target_2_requestor'} eq
                    $args{'target_1_name'} . $args{'target_1_requestor'}  ?
                    $targets[1]   :
                    $target_adaptor->fetch_by_name_and_requestor( $args{'target_2_name'}, $args{'target_2_requestor'}, );
    $targets[2]->designed( $options{designed} );
    
    # build crRNAs
    my @crRNAs;
    # convert names to chr, start, end, strand
    if( !$args{'crRNA_1_chr'} || !$args{'crRNA_1_start'} || !$args{'crRNA_1_end'} ||
        !$args{'crRNA_1_strand'} || !$args{'crRNA_2_chr'} || !$args{'crRNA_2_start'} ||
        !$args{'crRNA_2_end'} || !$args{'crRNA_2_strand'} ){
        
        if( $args{'crRNA_1_name'} && $args{'crRNA_2_name'} ){
            ( $args{'crRNA_1_chr'}, $args{'crRNA_1_start'},
                $args{'crRNA_1_end'}, $args{'crRNA_1_strand'}, ) = $crispr_design->parse_cr_name( $args{'crRNA_1_name'} );
            ( $args{'crRNA_2_chr'}, $args{'crRNA_2_start'},
                $args{'crRNA_2_end'}, $args{'crRNA_2_strand'}, ) = $crispr_design->parse_cr_name( $args{'crRNA_2_name'} );
            # check whether crRNAs already exist in db
            # if they do retrieve them from the db and add the name to already_exists hash
            my $missing = 0;
            my @missing_attributes;
            foreach my $cr_num ( 1, 2 ){
                if( $crRNA_adaptor->exists_in_db( $args{'crRNA_' . $cr_num . '_name'},
                        $args{'target_name'}, $args{'requestor'} ) ){
                    $crRNA_already_exists_in_db{ $args{'crRNA_' . $cr_num . '_name'} } = 1;
                    $crRNAs[$cr_num] =
                        $crRNA_adaptor->fetch_by_name_and_target(
                            $args{'crRNA_' . $cr_num . '_name'}, $targets[$cr_num] );
                }
                else{
                    # check we have enough info to add the crispr to the db
                    my @attributes = ( 'pair_name',
                                      'target_' . $cr_num . '_name', 
                                      'crRNA_' . $cr_num . '_start',
                                      'crRNA_' . $cr_num . '_end',
                                      'crRNA_' . $cr_num . '_target_sequence' );
                    foreach my $attribute ( @attributes ){
                        if( none { $_ eq $attribute } keys %args ){
                            $missing = 1;
                            push @missing_attributes, $attribute;
                        }
                    }
                    $all_in_db = 0;
                }
            }
            if( $missing ){
                die "crRNA does not exist yet in the db and there is not enough information to add it.\n",
                join("\n", map { join(" = ", $_, $args{$_} ) } keys %args ), "\n",
                'Required attributes: ', join(q{,}, @missing_attributes, ), "\n";
            }
        }
    }
    else{
        $crRNAs[1] = build_crRNA( $targets[1], \%args, 1, );
        $crRNAs[2] = build_crRNA( $targets[2], \%args, 2, );
    }
    
    if( $options{debug} == 2 ){
        warn Dumper( @crRNAs );
    }
    
    my $crispr_pair = Crispr::CrisprPair->new(
        target_1 => $targets[1],
        target_2 => $targets[2],
        crRNA_1 => $crRNAs[1],
        crRNA_2 => $crRNAs[2],
        paired_off_targets => $args{number_paired_off_target_hits},
    );
    
    push @crispr_pairs, $crispr_pair;
}

if( $options{debug} == 2 ){
    warn Dumper( %crRNA_already_exists_in_db );
    warn "All in db variable: $all_in_db\n";
}

# store crRNA pairs in database
eval{
    $crispr_pair_adaptor->store_crispr_pairs( \@crispr_pairs );
};
if( $EVAL_ERROR ){
    die "There was a problem storing one of the crispr pairs in the database.\n",
            "ERROR MSG:", $EVAL_ERROR, "\n";
}
else{
    foreach my $pair ( @crispr_pairs ){
        if( !exists $crRNA_already_exists_in_db{ $pair->crRNA_1->name } ){
            print join(q{ }, $pair->crRNA_1->name,
                     'was stored correctly in the database with id:',
                     $pair->crRNA_1->crRNA_id, ), "\n";
        }
        if( !exists $crRNA_already_exists_in_db{ $pair->crRNA_2->name } ){
            print join(q{ }, $pair->crRNA_2->name,
                     'was stored correctly in the database with id:',
                     $pair->crRNA_2->crRNA_id, ), "\n";
        }
        print join(q{ }, $pair->name,
                'was stored correctly in the database with id:',
                $pair->pair_id, ), "\n";
    }
}

if( !$all_in_db ){
    # make a new plate to fill for construction oligos
    my $plate_name = 'CR_' . sprintf("%06d", $options{plate_num}) . 'a';
    my $oligo_plate = Crispr::Plate->new(
        plate_id => undef,
        plate_name => $plate_name,
        plate_category => 'construction_oligos',
        plate_type => $options{plate_type},
        fill_direction => $options{fill_direction},
        ordered => $options{ordered},
        received => $options{received},
    );
    
    # fill plate with crisprs for adding construction oligos to db
    if( scalar @crispr_pairs * 2 <= $oligo_plate->plate_type ){
        # add plate to db
        eval{
            $plate_adaptor->store( $oligo_plate );
        };
        if( $EVAL_ERROR ){
            if( $EVAL_ERROR =~ m/PLATE\sALREADY\sEXISTS/xms ){
                warn join(q{ }, 'Construction Plate', $oligo_plate->plate_name,
                          'already exists in the database. Using this plate to add oligos to...'
                         ), "\n";
            }
            else{
                die "There was a problem storing the construction oligos plate in the database.\n",
                        "ERROR MSG:", $EVAL_ERROR, "\n";
            }
        }
        else{
            print join(q{ }, $oligo_plate->plate_name,
                       'was stored correctly in the database with id:',
                       $oligo_plate->plate_id, ), "\n";
        }
        # fill wells of the plate
        $oligo_plate->fill_wells_from_first_empty_well(
            [ map { @{$_->crRNAs} } @crispr_pairs ]
        );
    }
    else{
        die "More than one plate full of stuff!\n";
    }
    
    # return wells from plate and add to db
    my $wells = $oligo_plate->return_all_non_empty_wells;
    foreach my $well ( @{$wells} ){
        eval{
            $crRNA_adaptor->store_construction_oligos( $well );
        };
        if( $EVAL_ERROR ){
            warn "There was a problem storing one of the construction oligos in the database.\n",
                    "ERROR MSG:", $EVAL_ERROR, "\n";
        }
        else{
            print join(q{ }, 'Construction oligos for', $well->contents->name,
                    'were stored correctly in the database.'), "\n";
        }
    }
    
    # add expression constructs to db
    foreach my $suffix ( qw{ b c } ){
        my $construct_plate = Crispr::Plate->new(
            plate_id => undef,
            plate_category => 'expression_construct',
            plate_type => $options{plate_type},
            fill_direction => $options{fill_direction},
        );
        # add name to plate
        $plate_name = 'CR_' . sprintf("%06d", $options{plate_num}) . $suffix;
        $construct_plate->plate_name( $plate_name );
        
        # fill wells of the plate
        $construct_plate->fill_wells_from_first_empty_well(
            [ map { @{$_->crRNAs} } @crispr_pairs ]
        );
        
        # add plate to db
        eval{
            $plate_adaptor->store( $construct_plate );
        };
        if( $EVAL_ERROR ){
            if( $EVAL_ERROR =~ m/PLATE\sALREADY\sEXISTS/xms ){
                warn join(q{ }, 'Expression Plate', $construct_plate->plate_name,
                          'already exists in the database. Using this plate to add oligos to...'
                         ), "\n";
            }
            else{
                die "There was a problem storing the expression construct plate, ",
                    $construct_plate->plate_name, " in the database.\n",
                        "ERROR MSG:", $EVAL_ERROR, "\n";
            }
        }
        else{
            print join(q{ }, $construct_plate->plate_name,
                       'was stored correctly in the database with id:',
                       $construct_plate->plate_id, ), "\n";
        }
        
        # return wells from plate and add to db
        $wells = $construct_plate->return_all_non_empty_wells;
        foreach my $well ( @{$wells} ){
            eval{
                $crRNA_adaptor->store_expression_construct_info( $well );
            };
            if( $EVAL_ERROR ){
                warn "There was a problem storing the expression construct info, ",
                    join(':', $construct_plate->plate_name, $well->position, ),
                    " in the database.\n",
                        "ERROR MSG:", $EVAL_ERROR, "\n";
            }
            else{
                print join(q{ }, 'Expression Constructs for', $well->contents->name,
                    join(q{}, '(', $well->plate->plate_name, ' id: ',
                        $well->plate->plate_id, ')', ),
                    'were stored correctly in the database.',
                ), "\n";
            }
        }
    }
}

sub build_crRNA {
    my ( $target, $args, $num, ) = @_;
    
    my $crRNA = Crispr::crRNA->new(
        crRNA_id => undef,
        target => $target,
        chr => $args->{'crRNA_' . $num . '_chr'},
        start => $args->{'crRNA_' . $num . '_start'},
        end => $args->{'crRNA_' . $num . '_end'},
        strand => $args->{'crRNA_' . $num . '_strand'},
        sequence => $args->{'crRNA_' . $num . '_sequence'},
        species => $args->{species} || $target->species,
    );
    
    # off target info
    my $off_target_info;
    if( $args->{'crRNA_' . $num . '_off_target_hits'} ){
        $crRNA->off_target_hits(
            Crispr::OffTargetInfo->new(
                crRNA_name => $crRNA->name,
            )
        );
        my @off_targets = split /\|/, $args->{'crRNA_' . $num . '_off_target_hits'};
        if( defined $off_targets[0] && $off_targets[0] ne '' ){
            foreach ( split /\//, $off_targets[0] ){
                $crispr_design->make_and_add_off_target_from_position(
                    $crRNA, $_, 'exon',
                );
            }
        }
        if( defined $off_targets[1] && $off_targets[1] ne '' ){
            foreach ( split /\//, $off_targets[1] ){
                $crispr_design->make_and_add_off_target_from_position(
                    $crRNA, $_, 'intron',
                );
            }
        }
        if( defined $off_targets[2] && $off_targets[2] ne '' ){
            foreach ( split /\//, $off_targets[2] ){
                $crispr_design->make_and_add_off_target_from_position(
                    $crRNA, $_, 'nongenic',
                );
            }
        }
    }
    
    # add coding scores
    if( exists $args->{'crRNA_' . $num . '_coding_scores_by_transcript'} &&
        defined $args->{'crRNA_' . $num . '_coding_scores_by_transcript'} &&
        $args->{'crRNA_' . $num . '_coding_scores_by_transcript'} ne 'NULL' ){
        foreach ( split /;/, $args->{'crRNA_' . $num . '_coding_scores_by_transcript'} ){
            $crRNA->coding_score_for( split /=/, $_ );
        }
    }
    
    if( exists $args->{'crRNA_' . $num . '_five_prime_Gs'} &&
        defined $args->{'crRNA_' . $num . '_five_prime_Gs'} ){
        $crRNA->five_prime_Gs( $args->{'crRNA_' . $num . '_five_prime_Gs'} );
    }
    
    return $crRNA;
}

sub get_and_check_options {
    
    GetOptions(
        \%options,
        'crispr_db=s',
        'plate_num=i',
        'plate_type=s',
        'fill_direction=s',
        'species=s',
        'target_genome=s',
        'registry_file=s',
        'designed=s',
        'ordered=s',
        'received=s',
        'debug+',
        'help',
        'man',
    ) or pod2usage(2);
    
    # Documentation
    if ($options{help}) {
        pod2usage( -verbose => 0, -exitval => 1, );
    }
    elsif ($options{man}) {
        pod2usage( -verbose => 2 );
    }

    # Check options
    if( !$options{designed} ){
        $options{designed} = DateTime->now();
    }
    elsif( $options{designed} !~ m/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/xms ){
        pod2usage( "The date supplied for option --designed is not a valid format\n" );
    }
    else{
        $options{designed} = _parse_date_to_date_object( $options{designed} );
    }
    
    if( $options{ordered} ){
        if( $options{ordered} !~ m/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/xms ){
            pod2usage( "The date supplied for option --ordered is not a valid format\n Use YEAR-MONTH-DAY\n" );
        }
        else{
            $options{ordered} = _parse_date_to_date_object( $options{ordered} );
        }
    }
    
    if( $options{received} ){
        if( $options{received} !~ m/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/xms ){
            pod2usage( "The date supplied for option --received is not a valid format\n" );
        }
        else{
            $options{received} = _parse_date_to_date_object( $options{received} );
        }
    }
    
    #defaults
    $options{debug} = $options{debug}   ?   $options{debug} :   0;
    $options{species} = $options{species}   ?   $options{species} :   'zebrafish';
    $options{plate_num} = $options{plate_num}   ?   $options{plate_num} :   1;
    $options{plate_type} = $options{plate_type} ?   $options{plate_type}    :   '96';
    $options{fill_direction} = $options{fill_direction} ?   $options{fill_direction}    :   'column';

    return;
}

sub _parse_date_to_date_object {
    my ( $date ) = @_;
    
    $date =~ m/\A([0-9]{4})-([0-9]{2})-([0-9]{2})\z/xms;
    my $date_obj = DateTime->new(
        year       => $1,
        month      => $2,
        day        => $3,
    );
    return $date_obj;
}

__END__

=pod

=head1 NAME

add_crispr_pairs_to_db_from_file.pl

=head1 DESCRIPTION

Takes information on pairs of crispr target sites and enters it into a MySQL or SQLite database.
The script will accept just the names of the two crisprs if the crispr target sites have already been entered into the database.
Otherwise it will take the info on both crispr target sites in the pair and add everything to the database at once.

=head1 SYNOPSIS

    add_crispr_pairs_to_db_from_file.pl [options] filename(s) | target info on STDIN
        --crispr_db             config file for connecting to the database
        --plate_num             Plate number
        --plate_type            Type of plate (96 or 384) [default:96]
        --fill_direction        row or column [default:column]
        --registry_file         a registry file for connecting to the Ensembl database
        --designed              date on which the crisprs were designed
        --ordered               date on which the crisprs were ordered
        --received              date on which the crisprs were received
        --help                  prints help message and exits
        --man                   prints manual page and exits
        --debug                 prints debugging information
        input file | STDIN

=head1 REQUIRED ARGUMENTS

=over

=item B<input_file(s)>

Information on crispr pairs.

Should contain the following columns: 

=over

=item Either: pair_name number_paired_off_target_hits target_1_name target_1_requestor crRNA_1_name crRNA_2_name

=item Or: pair_name number_paired_off_target_hits
    target_1_name target_1_requestor
    crRNA_1_start crRNA_1_end crRNA_1_sequence
    crRNA_2_start crRNA_2_end crRNA_2_sequence

=back

Optional columns:
    combined_score deletion_size 
    target_1_species crRNA_1_chr crRNA_1_strand
    crRNA_1_score crRNA_1_oligo1 crRNA_1_oligo2
    crRNA_1_off_target_score crRNA_1_off_target_counts crRNA_1_off_target_hits
    crRNA_1_coding_score crRNA_1_coding_scores_by_transcript
    crRNA_1_five_prime_Gs crRNA_1_plasmid_backbone crRNA_1_GC_content
    target_2_name target_2_species target_2_requestor 
    crRNA_2_chr crRNA_2_strand
    crRNA_2_score crRNA_2_oligo1 crRNA_2_oligo2
    crRNA_2_off_target_score crRNA_2_off_target_counts crRNA_2_off_target_hits
    crRNA_2_coding_score crRNA_2_coding_scores_by_transcript
    crRNA_2_five_prime_Gs crRNA_2_plasmid_backbone crRNA_2_GC_content

=back

=head1 OPTIONS

=over 8

=item B<--crispr_db file>

Database config file containing tab-separated key value pairs.
keys are:

=over

=item driver

mysql or sqlite

=item host

database host name (MySQL only)

=item port

database host port (MySQL only)

=item user

database host user (MySQL only)

=item pass

database host password (MySQL only)

=item dbname

name of the database

=item dbfile

path to database file (SQLite only)

=back

The values can also be set as environment variables
At the moment MySQL is assumed as the driver for this.

=over

=item MYSQL_HOST

=item MYSQL_PORT

=item MYSQL_USER

=item MYSQL_PASS

=item MYSQL_DBNAME

=back

=item B<--plate_num integer>

Plate number to put construction oligos and expression constructs in.

=item B<--plate_type >

Type of plate (96 or 384 well) [default:96]

=item B<--fill_direction >

row or column [default:column]
fill_direction is ignored if well ids are explicitly supplied in the input.

=item B<--registry_file file>

a registry file for connecting to the Ensembl database

=item B<--designed >

date on which the crisprs were designed (YEAR-MONTH-DAY)

=item B<--ordered >

date on which the crisprs were ordered (YEAR-MONTH-DAY)

=item B<--received >

date on which the crisprs were received (YEAR-MONTH-DAY)

=item B<--debug>

Print debugging information.

=item B<--help>

Print a brief help message and exit.

=item B<--man>

Print this script's manual page and exit.

=back

=head1 AUTHOR

=over 4

=item *

Richard White <richard.white@sanger.ac.uk>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014 by Genome Research Ltd.

This is free software, licensed under:

  The GNU General Public License, Version 3, June 2007

=cut
