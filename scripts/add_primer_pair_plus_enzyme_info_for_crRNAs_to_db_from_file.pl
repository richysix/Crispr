#!/usr/bin/env perl
# add_primer_pair_plus_enzyme_info_for_crRNAs_to_db_from_file.pl

use warnings; use strict;
use autodie;
use Getopt::Long;
use English qw( -no_match_vars );
use Pod::Usage;
use Data::Dumper;
use DateTime;
use Readonly;
use List::MoreUtils qw( any none );
use Bio::EnsEMBL::Registry;
use Bio::Restriction::EnzymeCollection;
use Bio::Seq;

use Crispr::crRNA;
use Crispr::PrimerPair;
use Crispr::Primer;
use Crispr::EnzymeInfo;
use Crispr::DB::DBConnection;
use Crispr::DB::crRNAAdaptor;
use Crispr::Config;


my $comment_regex = qr/#/;

my %plate_suffixes = (
    ext => 'd',
    int => 'e',
    'ext-illumina' => 'f',
    'int-illumina' => 'g',
    'int-illumina_tailed' => 'h',
);

my %options;
get_and_check_options();

# check registry file
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

my $slice_adaptor = Bio::EnsEMBL::Registry->get_adaptor( $options{species}, 'core', 'slice' );

# connect to crispr db
my $db_connection = Crispr::DB::DBConnection->new( $options{crispr_db}, );

# get Adaptors using database adaptor
my $crRNA_adaptor = $db_connection->get_adaptor( 'crRNA' );
my $primer_adaptor = $db_connection->get_adaptor( 'primer' );
my $primer_pair_adaptor = $db_connection->get_adaptor( 'primer_pair' );
my $plate_adaptor = $db_connection->get_adaptor( 'plate' );

my @attributes = (
    qw{ well_id product_size crRNA_names 
        left_primer_info right_primer_info enzyme_info }
);

my @required_attributes = (
    qw{ product_size crRNA_names left_primer_info right_primer_info }
);

my $complete_collection;
if( $options{rebase_file} && -e $options{rebase_file} ){
    my $rebase = Bio::Restriction::IO->new(
        -file   => $options{rebase_file},
        -format => 'withrefm'
    );
    $complete_collection = $rebase->read();
}
else{
    $complete_collection = Bio::Restriction::EnzymeCollection->new();
}

my $has_well_ids;
my $has_enzyme_info;
my %well_id_for;
my %crRNAs_for;
my @primer_pairs;
my @crisprs;
my @columns;

my @primer_plates;
if( $options{plate_num} ){
    foreach my $direction ( qw{ left right } ){
        # make a new plate to fill with primers
        my $plate_name = 'CR_' . sprintf("%06d", $options{plate_num}) . $plate_suffixes{ $options{type} };
        my $primer_plate = Crispr::Plate->new(
            plate_id => undef,
            plate_name => $plate_name,
            plate_category => 'pcr_primers',
            plate_type => $options{plate_type},
            fill_direction => $options{fill_direction},
            ordered => $options{ordered},
            received => $options{received},
        );
        push @primer_plates, $primer_plate;
    }
}

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
            if( none { $column_name eq $_ } @attributes ){
                die "Could not recognise column name, ", $column_name, ".\n";
            }
        }
        foreach my $attribute ( @required_attributes ){
            if( none { $attribute eq $_ } @columns ){
                die "Missing required attribute: ", $attribute, ".\n";
            }
        }
        if( any { $_ eq 'well_id' } @columns ){
            $has_well_ids = 1;
            warn "Input has well ids. Option --fill_direction will be ignored even if specified.\n";
        }
        if( any { $_ eq 'enzyme_info' } @columns  ){
            $has_enzyme_info = 1;
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
    
    # get crRNAs from db
    my @crRNAs;
    foreach ( split /,/, $args{'crRNA_names'} ){
        push @crRNAs, $crRNA_adaptor->fetch_by_name( $_ );
    }
    
    # parse primer info
    foreach my $direction ( qw{ left right } ){
        my ( $name, $seq ) = split /,/, $args{ "${direction}_primer_info" };
        my ( $chr, $region, $strand ) = split /:/, $name;
        my ( $start, $end ) = split /-/, $region;
        
        # make primer
        my $primer = Crispr::Primer->new(
                primer_name => $name,
                seq_region => $chr,
                seq_region_start => $start,
                seq_region_end => $end,
                seq_region_strand => $strand,
                sequence => $seq,
            );
        $args{"${direction}_primer"} = $primer;
        
        if( $options{plate_num} ){
            my $primer_plate = $direction eq 'left'  ?  $primer_plates[0]
                :                                       $primer_plates[1];
            if( $has_well_ids ){
                $primer_plate->fill_well( $primer, $args{well_id} );
            }
            else{
                $primer_plate->fill_wells_from_first_empty_well( [ $primer ] );
            }
        }
    }
    
    # make primer_pair object
    my $primer_pair = Crispr::PrimerPair->new(
        pair_name => join(":", $args{"left_primer"}->seq_region,
                    join("-", $args{"left_primer"}->seq_region_start,
                            $args{"right_primer"}->seq_region_end, ),
                    "1", ),
        type => $options{type},
        left_primer => $args{"left_primer"},
        right_primer => $args{"right_primer"},
        product_size => $args{"product_size"},
    );
    
    # parse enzyme info
    my $enzyme_info;
    # and a new full collection
    if( exists $args{ enzyme_info } ){
        # get sequence for int product and do restriction digest
        my ( $chr, $start, $end );
        next if( $primer_pair->type ne 'int' );
        $chr = $primer_pair->left_primer->seq_region;
        if( $primer_pair->left_primer->seq_region_strand eq '1' ){
            $start = $primer_pair->left_primer->seq_region_start;
            $end = $primer_pair->right_primer->seq_region_end;
        }
        else{
            $start = $primer_pair->right_primer->seq_region_start;
            $end = $primer_pair->left_primer->seq_region_end;
        }
        my $slice = $slice_adaptor->fetch_by_region( 'toplevel', $chr, $start, $end, '1', );
        my $amplicon = Bio::Seq->new(
            -seq => $slice->seq,
            -molecule => 'dna'
        );
        
        my $crRNA_i = 0;
        foreach my $info ( split /;/, $args{ enzyme_info } ){
            # make a new empty RE collection
            my $unique_cutters = Bio::Restriction::EnzymeCollection->new( -empty => 1 );
            
            my $crRNA = $crRNAs[$crRNA_i];
            # make slice for around crRNA target
            my $crRNA_slice = $slice_adaptor->fetch_by_region('toplevel', $crRNA->chr, $crRNA->start, $crRNA->end, $crRNA->strand, );
            my ( $left_expand, $right_expand ) = ( 0, 15 );
            # check that this would not go off the chromosome and adjust if necessary
            if( $crRNA->strand eq '1' && $crRNA_slice->seq_region_length - $crRNA_slice->end < 15 ){
                $right_expand = $crRNA_slice->seq_region_length - $crRNA_slice->end;
            } elsif( $crRNA->{strand} eq '-1' && $crRNA_slice->start - 1 < 15 ){
                $right_expand = $crRNA_slice->start - 1;
            }
            my $slice_for_re = $crRNA_slice->expand( $left_expand, $right_expand );
            my $crRNA_seq = Bio::PrimarySeq->new(
                -seq => $slice_for_re->seq,
                -primary_id => $crRNA->name,
                -molecule => 'dna'
            );
            
            # get a set of enzymes
            foreach my $enzyme_info ( split /,/, $info ){
                my ($enzyme_name, $site, $proximity ) = split /:/, $enzyme_info;
                # get enzyme object from enzyme_collection
                my @unique_cutters = grep { $_->name() eq $enzyme_name } $complete_collection->each_enzyme();
                if( !@unique_cutters ){
                    warn "Couldn't find the restriction enzyme, $enzyme_name. Ignoring...\n";
                }
                $unique_cutters->enzymes( @unique_cutters );
            }
            
            # do the digest on both the crispr target slice and the amplicon
            my $crRNA_re_analysis = Bio::Restriction::Analysis->new(
                -seq => $crRNA_seq,
                -enzymes => $unique_cutters,
            );
            
            my $ra = Bio::Restriction::Analysis->new(
                -seq => $amplicon,
                -enzymes => $unique_cutters,
            );
            
            $enzyme_info = Crispr::EnzymeInfo->new(
                crRNA => $crRNA,
                analysis => $crRNA_re_analysis,
                amplicon_analysis => $ra,
            );
            $crRNA->unique_restriction_sites( $enzyme_info );
            #increment crRNA index
            $crRNA_i++;
        }
    }
    
    push @primer_pairs, $primer_pair;
    push @{ $crRNAs_for{ $primer_pair->pair_name } }, @crRNAs;
    
}

if( $options{debug} > 2 ){
    print "crRNAs_for: \n", Dumper( %crRNAs_for );
    print "primer_pairs: \n", Dumper( @primer_pairs );
    print "plates: \n", Dumper( @primer_plates );
    exit;
}

# add primers to db
if( $options{plate_num} ){
    foreach my $primer_plate ( @primer_plates ){
        eval{
            $plate_adaptor->store( $primer_plate );
        };
        if( $EVAL_ERROR ){
            if( $EVAL_ERROR =~ m/PLATE\sALREADY\sEXISTS/xms ){
                warn join(q{ }, 'Primer Plate', $primer_plate->plate_name,
                          'already exists in the database. Using this plate to add oligos to...'
                         ), "\n";
            }
            else{
                die "There was a problem storing the primer plate in the database.\n",
                        "ERROR MSG:", $EVAL_ERROR, "\n";
            }
        }
        else{
            print join(q{ }, $primer_plate->plate_name,
                       'was stored correctly in the database with id:',
                       $primer_plate->plate_id, ), "\n";
        }
        
        # return wells from plate and add to db
        my $wells = $primer_plate->return_all_non_empty_wells;
        foreach my $well ( @{$wells} ){
            eval{
                $primer_adaptor->store( $well );
            };
            if( $EVAL_ERROR ){
                die "There was a problem storing one of the primers in the database.\n",
                        "ERROR MSG:", $EVAL_ERROR, "\n";
            }
            else{
                print join(q{ }, 'Primer', $well->contents->primer_name,
                        'was stored correctly in the database.'), "\n";
            }
        }
    }
}
else{
    foreach my $direction ( qw{ left right } ){
        my @primers = map { $direction eq 'left'   ?    $_->left_primer
                :                                       $_->right_primer } @primer_pairs;
        foreach my $primer ( @primers ){
            eval{
                $primer_adaptor->store( $primer );
            };
            if( $EVAL_ERROR ){
                die "There was a problem storing one of the primers in the database.\n",
                        "ERROR MSG:", $EVAL_ERROR, "\n";
            }
            else{
                print join(q{ }, 'Primer', $primer->primer_name,
                        'was stored correctly in the database.'), "\n";
            }
        }
    }
}

# add primer pairs to db
foreach my $primer_pair ( @primer_pairs ){
    eval{
        $primer_pair_adaptor->store( $primer_pair, $crRNAs_for{ $primer_pair->pair_name }, );
    };
    if( $EVAL_ERROR ){
        die "There was a problem storing one of the primer pairs in the database.\n",
                "ERROR MSG:", $EVAL_ERROR, "\n";
    }
    else{
        print join(q{ }, 'Primer Pair', $primer_pair->pair_name,
                'was stored correctly in the database.'), "\n";
    }
    
    # add enzyme info if it exists
    if( $has_enzyme_info ){
        foreach my $crRNA ( @{ $crRNAs_for{ $primer_pair->pair_name } } ){
            if( !$crRNA->unique_restriction_sites ){
                warn "No Enzyme Info for ", $crRNA->name, ".\n";
                next;
            }
            eval{
                $crRNA_adaptor->store_restriction_enzyme_info( $crRNA, $primer_pair );
                
            };
            if( $EVAL_ERROR ){
                die "There was a problem storing the enzyme info for one of the primer pairs in the database.\n",
                        "ERROR MSG:", $EVAL_ERROR, "\n";
            }
            else{
                print join(q{ }, 'Enzyme Info for primer pair', $primer_pair->pair_name,
                        'was stored correctly in the database.'), "\n";
            }
        }
    }
}

sub get_and_check_options {
    
    GetOptions(
        \%options,
        'crispr_db=s',
        'rebase_file=s',
        'plate_num=i',
        'plate_type=s',
        'type=s',
        'fill_direction=s',
        'registry_file=s',
        'species=s',
        'ordered=s',
        'received=s',
        'debug+',
        'help',
        'man',
    ) or pod2usage(2);
    
    # Documentation
    if ($options{help}) {
        pod2usage( -verbose => 0, exitval => 1, );
    }
    elsif ($options{man}) {
        pod2usage( -verbose => 2 );
    }
    
    # Check options
    if( !$options{plate_num} ){
        my $continue;
        while( !$continue ){
            print <<END_ST;
Option --plate_num has not been specified.
Enter 0 if you want to continue without a plate.
Enter a number if not...
END_ST
            my $response = <STDIN>;
            chomp $response;
            if( $response =~ m/\d+/ ){
                $options{plate_num} = $response == 0 ?   undef
                    :                           $response;
                $continue = 1;
            }
            else{
                print <<END_RESPONSE
That isn't a number. Please enter a number.
END_RESPONSE
            }
        }
    }
    
    # first check type is one of required ones
    if( !defined $options{type} ){
        die "option --type must be specified!\n";
    }
    elsif( !exists $plate_suffixes{ $options{type} } ){
        die join(q{ }, 'Primer type', $options{type}, 'is not a recognised type!', ), "\n",
            "Accepted types are: ", join(q{ }, sort keys %plate_suffixes ), "\n";
    }
    
    if( !$options{ordered} ){
        $options{ordered} = DateTime->now();
    }
    elsif( $options{ordered} !~ m/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/xms ){
        pod2usage( "The date supplied for option --ordered is not a valid format\n" );
    }
    else{
        $options{ordered} = _parse_date_to_date_object( $options{ordered} );
    }
    
    if( $options{received} ){
        if( $options{received} !~ m/\A[0-9]{4}-[0-9]{2}-[0-9]{2}\z/xms ){
            pod2usage( "The date supplied for option --received is not a valid format\n" );
        }
        else{
            $options{received} = _parse_date_to_date_object( $options{received} );
        }
    }
    
    # defaults options
    #my ( $dbhost, $dbport, $dbuser, $dbpass );
    $options{debug} = $options{debug}   ?   $options{debug} :   0;
    $options{plate_type} = $options{plate_type} ?   $options{plate_type}    :   '96';
    $options{fill_direction} = $options{fill_direction} ?   $options{fill_direction}    :   'column';
    $options{rebase_file} = $options{rebase_file}   ?   $options{rebase_file}   :   '/nfs/users/nfs_r/rw4/config/current_rebase.re';
    $options{species} = $options{species}   ?   $options{species}   :   'zebrafish';

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

add_primer_pair_plus_enzyme_info_for_crRNAs_to_db_from_file.pl

=head1 DESCRIPTION

Takes information on primer pairs for crispr guides and enters it into a MySQL database.

=head1 SYNOPSIS

    add_primer_pair_plus_enzyme_info_for_crRNAs_to_db_from_file.pl [options] input_file(s) | target info on STDIN
        --crispr_db             config file for connecting to the database
        --rebase_file           Rebase restriction enzyme file
        --type                  Primer type (ext, int, illumina, illumina_tailed )
        --plate_num             Plate number to add primers to
        --plate_type            Plate type (96 or 384)
        --fill_direction        Direction in which to fill the plate (row or column) [default:column]
        --registry_file         a registry file for connecting to the Ensembl database
        --ordered               date on which the primers were ordered
        --received              date on which the primers were received
        --help                  prints help message and exits
        --man                   prints manual page and exits
        --debug                 prints debugging information
        input file | STDIN

=head1 REQUIRED ARGUMENTS

=over

=item B<input_file>

Information on primer pairs.

Should contain the following columns:

 * product_size       - size of PCR product (Int)
 * crRNA_names        - comma-separated list of crRNAs covered by amplicon
 * left_primer_info   - comma-separated list (primer_name,sequence)
 * right_primer_info  - comma-separated list (primer_name,sequence)

Optional columns are:

 * well_id            - well id to use for adding primers to db.
    (A01-H12 for 96 well plates. A01-P24 for 384 well plates.)
 * enzyme_info        - comma-separated list of enzymes that cut the amplicon
    and the crispr target site uniquely
    each item should consist of Enzyme_name:Site:Distance_to_crispr_cut_site

=item B<--type>

Type of primers. One of ext, int, illumina, illumina_tailed.

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

=item B<--rebase_file>

File of restriction enzyme data from REBASE (rebase.neb.com/rebase/rebase.html).

=item B<--plate_num>

Base plate number to put primers in. Integer.
A suffix is added to the plate_name depending on the type of primers.

  ext = d
  int = e
  ext-illumina => f
  int-illumina => g
  int-illumina_tailed => h
  
=item B<--plate_type >

Type of plate (96 or 384 well) [default:96]

=item B<--fill_direction >

row or column [default:column]
fill_direction is ignored if well ids are explicitly supplied in the input.

=item B<--registry_file>

a registry file for connecting to the Ensembl database

=item B<--ordered >

date on which the crisprs were ordered (YEAR-MONTH-DAY)

=item B<--received >

date on which the crisprs were received (YEAR-MONTH-DAY)

=item B<--debug>

Print debugging information.

=item B<--help>

Prints a help message and exits

=item B<--man>

Prints the man page and exits

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

