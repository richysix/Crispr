#!/usr/bin/env perl

# PODNAME: add_samples_and_analysis_to_db_from_file.pl
# ABSTRACT: Add information about samples and analysis information
# to a CRISPR SQL database from a sample manifext file.

use warnings;
use strict;
use Getopt::Long;
use autodie;
use Pod::Usage;
use English qw( -no_match_vars );
use List::MoreUtils qw( none );

use Crispr::DB::DBConnection;
use Crispr::DB::Plex;
use Crispr::DB::SampleAmplicon;
use Crispr::DB::Analysis;
use Crispr::DB::Sample;
use Crispr::Plate;
use Labware::Plate;

# get options
my %options;
get_and_check_options();

# connect to db
my $db_connection = Crispr::DB::DBConnection->new( $options{crispr_db}, );
my $plex_adaptor = $db_connection->get_adaptor( 'plex' );
my $injection_pool_adaptor = $db_connection->get_adaptor( 'injection_pool' );
my $analysis_adaptor = $db_connection->get_adaptor( 'analysis' );
my $sample_adaptor = $db_connection->get_adaptor( 'sample' );
my $primer_pair_adaptor = $db_connection->get_adaptor( 'primer_pair' );

# set up barcode and sample plates
my $barcode_plates = set_up_barcode_plates();

# make a minimal plate for parsing well-ranges
my $sample_plate = Crispr::Plate->new(
    plate_category => 'samples',
    plate_type => $options{sample_plate_format},
    fill_direction => $options{sample_plate_fill_direction},
);

# make a minimal plate for parsing well-ranges
my $miseq_plate = Crispr::Plate->new(
    plate_category => 'samples',
    plate_type => $options{miseq_plate_format},
    fill_direction => $options{miseq_plate_fill_direction},
);

# Create Plex object and check it exists in the db
my $plex;
eval {
    $plex = $plex_adaptor->fetch_by_name( $options{plex_name} );
};
if( $EVAL_ERROR ){
    if( $EVAL_ERROR =~ qr/Couldn't retrieve plex, $options{plex_name}, from database./ ){
        $plex = Crispr::DB::Plex->new(
            plex_name => $options{plex_name},
            run_id => $options{run_id},
            analysis_started => $options{analysis_started},
            analysis_finished => $options{analysis_finished},
        );
        $plex_adaptor->store( $plex );
    }
    else{
        die $EVAL_ERROR, "\n";
    }
}

# parse input file, create Sample objects and add them to db
my @attributes = ( qw{ injection_name sample_wells num_samples
cryo_box generation sample_type species miseq_plate_num miseq_wells
barcodes barcode_plate_num amplicons } );

my @required_attributes = ( qw{ injection_name generation sample_type species
miseq_plate_num miseq_wells amplicons } );

my $comment_regex = qr/#/;
my @columns;
my @analyses;
my %primer_pair_cache;

# go through input
while(<>){
    my @values;

    chomp;
    if( $INPUT_LINE_NUMBER == 1 ){
        if( !m/\A $comment_regex/xms ){
            die "Input needs a header line starting with a #\n";
        }
        s|$comment_regex||xms;
        @columns = split /\t/, $_;
        my ( $wells, $numbers, $barcodes, $barcode_plate_num );
        foreach my $column_name ( @columns ){
            if( none { $column_name eq $_ } @attributes ){
                die "Could not recognise column name, ", $column_name, ".\n";
            }
            $wells = 1 if $column_name eq 'sample_wells';
            $numbers = 1 if $column_name eq 'num_samples';
            $barcodes = 1 if $column_name eq 'barcodes';
            $barcode_plate_num = 1 if $column_name eq 'barcode_plate_num';
        }
        foreach my $attribute ( @required_attributes ){
            if( none { $attribute eq $_ } @columns ){
                die "Missing required attribute: ", $attribute, ".\n";
            }
        }
        if( !( $wells xor $numbers ) ){
            die "Input file must include only one of sample_wells or num_samples!\n";
        }
        if( !( $barcodes xor $barcode_plate_num ) ){
            die "Input file must include only one of barcodes or barcode_plate_num!\n";
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
    warn Dumper( %args ) if $options{debug} > 1;

    # get injection pool object
    $args{'injection_pool'} = $injection_pool_adaptor->fetch_by_name( $args{'injection_name'} );
    # get any existing samples
    my $samples;
    eval{
        $samples = $sample_adaptor->fetch_all_by_injection_pool( $args{'injection_pool'} );
    };
    if( $EVAL_ERROR ){
        if( $EVAL_ERROR !~ m/Couldn't\sretrieve\ssamples\sfor\sinjection\sid,\s\d+\sfrom\sdatabase/xms ){
            die $EVAL_ERROR;
        }
    }

    my @sample_numbers;
    if( $samples ){
        @sample_numbers = sort { $b <=> $a }
                            map { $_->sample_number } @{$samples};
    }
    my $starting_sample_number = @sample_numbers
        ?   $sample_numbers[0]
        :   0;

    my @well_ids;
    if( defined $args{sample_wells} ){
        @well_ids = $sample_plate->parse_wells( $args{sample_wells} );
    }
    my $num_samples = @well_ids ? scalar @well_ids : $args{num_samples};

    my @barcodes;
    if( $args{barcodes} ){
        @barcodes = parse_barcodes( $args{barcodes} );
    }
    elsif( $args{barcode_plate_num} ){
        foreach my $well_id ( @well_ids ){
            my $plate_i = $args{barcode_plate_num} - 1;
            my $barcode = $barcode_plates->[$plate_i]->return_well( $well_id )->contents();
            push @barcodes, $barcode;
        }
    }
    # check there's the same number of barcodes and wells
    if( scalar @barcodes != scalar @well_ids ){
        die join("\n", "Number of barcodes is not the same as the number of wells",
                   $_, ), "\n";
    }

    my @miseq_well_ids = $miseq_plate->parse_wells( $args{miseq_wells} );

    # fetch primer_pairs from db
    my @primer_pairs;
    foreach my $amplicon_info ( split /,/, $args{'amplicons'} ){
        if( !exists $primer_pair_cache{$amplicon_info} ){
            my ( $plate_num, $well_id ) = split /_/, $amplicon_info;
            my $plate_name = sprintf("CR_%06dh", $plate_num, );
            if( length $well_id == 2 ){
                substr($well_id, 1, 0, '0');
            }
            my $primer_pair =
                $primer_pair_adaptor->fetch_by_plate_name_and_well(
                                        $plate_name, $well_id );
            if( defined $primer_pair ){
                push @primer_pairs, $primer_pair;
                $primer_pair_cache{$amplicon_info} = $primer_pair;
            }
        }
        else{
            push @primer_pairs, $primer_pair_cache{$amplicon_info};
        }
    }
    if( !@primer_pairs ){
        die "Primer pairs for the given plate and well don't exist in the database.\n",
            $_;
    }

    my @sample_amplicons;
    foreach my $sample_number ( $starting_sample_number + 1 .. $starting_sample_number + $num_samples ){
        my $well_id = shift @well_ids;
        my $barcode_id = shift @barcodes;
        my $miseq_well_id = shift @miseq_well_ids;
        $args{'well'} = defined $well_id ? Labware::Well->new( position => $well_id, )
            :       undef;
        # make new sample object
        $args{'sample_name'} = join("_", $args{'injection_name'}, $sample_number, );
        $args{'sample_number'} = $sample_number;
        my $sample = Crispr::DB::Sample->new( \%args );
        my $sample_amplicon = Crispr::DB::SampleAmplicon->new(
            sample => $sample,
            amplicons => \@primer_pairs,
            barcode_id => $barcode_id,
            plate_number => $args{'miseq_plate_num'},
            well_id => $miseq_well_id,
        );
        push @sample_amplicons, $sample_amplicon;
    }

    # make new analysis object
    my $analysis = Crispr::DB::Analysis->new(
        db_id => $args{analysis_id} || undef,
        plex => $plex,
        analysis_started => $options{analysis_started},
        analysis_finished => $options{analysis_finished},
        info => \@sample_amplicons,
    );
    push @analyses, $analysis;

}

if( $options{debug} > 1 ){
    warn Dumper( @analyses, );
}

foreach my $analysis ( @analyses ){
    eval{
        $analysis_adaptor->store_analysis( $analysis );
    };
    if( $EVAL_ERROR ){
        die join(q{ }, "There was a problem storing one of the analysis in the database.\n",
                "ERROR MSG:", $EVAL_ERROR, ), "\n";
    }
    else{
        print join(q{ }, 'Analysis was stored correctly in the database with id:',
            $analysis->db_id,
        ), "\n";
    }
}

# parse_wells
#Usage       :   my @wells = parse_wells( $wells, );
#Purpose     :   split up either a comma-separated list or range of well ids
#               into an array of well ids
#Returns     :   Array of Str
#Parameters  :   Str (Either comma-separated list or range like A1-A24)
#Throws      :
#Comments    :

sub parse_wells {
    my ( $wells, $plate ) = @_;
    my @wells;
    $wells = uc($wells);
    if( $wells =~ m/\A [A-P]\d+             # single well e.g. A1 or B01
                        \z/xms ){
        @wells = ( $wells );
    }
    elsif( $wells =~ m/\A [A-P]\d+          # well_id
                            ,+              # zero or more commas
                            [A-P]\d+        # well_id e.g. A01,A02,A03,A04
                        /xms ){
        @wells = split /,/, $wells;
    }
    elsif( $wells =~ m/\A  [A-P]\d+         # well_id
                            \-              # literal hyphen
                            [A-P]\d+        # well_id e.g. A1-B3
                        \z/xms ){
        @wells = $plate->range_to_well_ids( $wells );
    }
    else{
        die "Couldn't understand wells, $wells!\n";
    }
    foreach my $well ( @wells ){
        if( length $well == 2 ){
            $well =~ substr($well,1,0,"0");
        }
    }

    if( $options{debug} > 1 ){
        warn "@wells\n";
    }
    return @wells;
}

# parse_barcodes
#Usage       :   my @barcodes = parse_barcodes( $barcodes, );
#Purpose     :   split up either a comma-separated list or a number range into an array
#Returns     :   Array of Int
#Parameters  :   Str
#Throws      :
#Comments    :

sub parse_barcodes {
    my ( $barcodes, ) = @_;
    my @barcodes = parse_number_range( $barcodes, 'barcodes' );
    if( $options{debug} > 1 ){
        warn "@barcodes\n";
    }
    return @barcodes;
}

# parse_number_range
#Usage       :   my @sample_numbers = parse_number_range( $numbers, $type );
#Purpose     :   split up either a comma-separated list or a number range into an array
#Returns     :   Array of Int
#Parameters  :   Str (Either comma-separated list or range like 1-24)
#                Str (Type - Either barcodes or sample_numbers)
#Throws      :
#Comments    :

sub parse_number_range {
    my ( $number_range, $type, ) = @_;

    my @numbers;
    if( $number_range =~ m/\A \d+ \z/xms ){
        @numbers = ( $number_range );
    }
    elsif( $number_range =~ m/\A \d+       #digits
                            ,+      # zero or more commas
                            \d+     # digits
                        /xms ){
        @numbers = split /,/, $number_range;
    }
    elsif( $number_range =~ m/\A \d+        # digits
                            \-          # literal hyphen
                            \d+         # digits
                            \z/xms ){
        my ( $start, $end ) = split /-/, $number_range;
        @numbers = ( $start .. $end );
    }
    else{
        die "Couldn't understand ", $type, q{, }, $number_range, "!\n";
    }
    return @numbers;
}

# set_up_barcode_plates
#Usage       :   my @barcode_plates = set_up_barcode_plates();
#Purpose     :   Produce and return an Array of barcode plates for assigning
#                barcode indexes to samples
#Returns     :   Arrayref of Labware::Plate objects
#Parameters  :   None
#Throws      :
#Comments    :   Assumes there are 384 barcodes.
#                It will produce 4 x 96 well plates or 1 x 384 well plate
#                depending on the barcode plate format

sub set_up_barcode_plates {

    my @barcode_plates;
    if( $options{barcode_plate_format} eq '96' ){
        # make 4 x 96 well plates
        foreach my $plate_num ( 1..4 ){
            # create empty plate
            my $barcode_plate = Labware::Plate->new(
                plate_name => join("-", 'barcode_plate', $plate_num, ),
                plate_type => $options{barcode_plate_format},
                fill_direction => $options{barcode_plate_fill_direction},
            );

            # fill plate with barcode indexes
            my $starting_index = 96 * ($plate_num - 1) + 1;
            my $end_index = 96 * ($plate_num - 1) + 96;
            my @barcode_indexes = ( $starting_index .. $end_index );
            $barcode_plate->fill_wells_from_first_empty_well( \@barcode_indexes );
            push @barcode_plates, $barcode_plate;
        }
    }
    elsif( $options{barcode_plate_format} eq '384' ){
        if( $options{barcode_plate_fill_direction} eq 'row' || $options{barcode_plate_fill_direction} eq 'column' ){
            my $barcode_plate = Labware::Plate->new(
                plate_name => 'barcode_plate-1',
                plate_type => $options{barcode_plate_format},
                fill_direction => $options{barcode_plate_fill_direction},
            );
            my @barcode_indexes = ( 1 .. 384 );
            $barcode_plate->fill_wells_from_first_empty_well( \@barcode_indexes );
            push @barcode_plates, $barcode_plate;
        }
        elsif( $options{barcode_plate_fill_direction} =~ m/\A quadrants _ (\d{4}) \z/xms ){
            # check quadrant order
            my @quadrant_order = split //, $1;
            foreach my $quadrant ( 1..4 ){
                my $count = scalar grep { $quadrant eq $_ } @quadrant_order;
                if( $count == 0 ){
                    die "Not all the quadrants are included in option --barcode_plate_fill_direction $options{barcode_plate_fill_direction}.\n";
                }
                elsif( $count > 1 ){
                    die "One of the quadrants is specified more than once in option --barcode_plate_fill_direction $options{barcode_plate_fill_direction}.\n";
                }
            }

            # make 4 x 96 plates and merge by_quadrants
            my @barcode_plates_96;
            foreach my $plate_num ( 1..4 ){
                # create empty plate
                my $barcode_plate = Labware::Plate->new(
                    plate_name => join("-", 'barcode_plate', $plate_num, ),
                    plate_type => '96',
                    fill_direction => 'row',
                );

                # fill plate with barcode indexes
                my $starting_index = 96 * ($plate_num - 1) + 1;
                my $end_index = 96 * ($plate_num - 1) + 96;
                my @barcode_indexes = ( $starting_index .. $end_index );
                $barcode_plate->fill_wells_from_first_empty_well( \@barcode_indexes );
                push @barcode_plates_96, $barcode_plate;
            }

            my $barcode_plate = Labware::Plate->new(
                plate_name => 'barcode_plate-1',
                plate_type => $options{barcode_plate_format},
                fill_direction => 'row',
            );

            foreach my $plate ( @barcode_plates_96 ){
                my $quadrant = shift @quadrant_order;
                add_96_well_plate_to_quadrant( $barcode_plate, $plate, $quadrant );
            }
            push @barcode_plates, $barcode_plate;
        }
        else{
            die "Couldn't understand option --barcode_plate_fill_direction $options{barcode_plate_fill_direction}.\n";
        }
    }
    else{
        die "Barcode plate: format must be either 96 or 384.\n";
    }
    if( $options{debug} > 1 ){
        warn Dumper( @barcode_plates );
    }
    return( \@barcode_plates, );
}

# add_96_well_plate_to_quadrant
#Usage       :  add_96_well_plate_to_quadrant( $barcode_plate, $plate, $quadrant )
#Purpose     :  Takes a 384 well barcode plate and adds a source 96 well barcode plate into a specific quadrant
#Returns     :
#Parameters  :  Labware::Plate (barcode plate)
#               Labware::Plate (96 well barcode plate)
#               Int (quadrant number)
#Throws      :
#Comments    :  Quadrants are numbered like this:
#               1   A01, A03 .. A23, C01, C03 .. C23 etc.
#               2   A02, A04 .. A24, C02, C04 .. C24 etc.
#               3   B01, B03 .. B23, D01, D03 .. D23 etc.
#               4   B02, B04 .. B24, D02, D04 .. D24 etc.

sub add_96_well_plate_to_quadrant{
    my ( $barcode_plate, $plate, $quadrant ) = @_;

    my %quadrant_rows = (
        1 => [ qw{ A C E G I K M O } ],
        2 => [ qw{ A C E G I K M O } ],
        3 => [ qw{ B D F H J L N P } ],
        4 => [ qw{ B D F H J L N P } ],
    );
    my %quadrant_cols = (
        1 => [ qw{ 01 03 05 07 09 11 13 15 17 19 21 23 } ],
        2 => [ qw{ 02 04 06 08 10 12 14 16 18 20 22 24 } ],
        3 => [ qw{ 01 03 05 07 09 11 13 15 17 19 21 23 } ],
        4 => [ qw{ 02 04 06 08 10 12 14 16 18 20 22 24 } ],
    );
    my ( $rowi, $coli ) = ( 0, 0 );

    foreach my $well ( @{ $plate->return_all_non_empty_wells } ){
        my $barcode_well = $quadrant_rows{$quadrant}->[$rowi] . $quadrant_cols{$quadrant}->[$coli];
        $barcode_plate->fill_well( $well->contents, $barcode_well );
        ( $rowi, $coli ) = increment_indices( $rowi, $coli );
    }
}

# increment_indices
#Usage       :   ( $rowi, $coli, ) = increment_indices( $rowi, $coli, );
#Purpose     :   Increment row and column indices
#Returns     :   Int (row index)
#                Int (col index)
#Parameters  :   Int (row index)
#                Int (col index)
#Throws      :   If row index becomes larger than 8
#Comments    :   Increments row-wise (i.e. A01, A02, A03 etc)

sub increment_indices {
    my ( $rowi, $coli, ) = @_;
    $coli++;
    if( $coli > 11 ){
        $coli = 0;
        $rowi++;
    }
    if( $rowi > 8 ){
        die "Ended up off the plate!\n";
    }
    return ( $rowi, $coli, );
}

# get_and_check_options
#Usage       :   get_and_check_options();
#Purpose     :   Get command line options and process them
#Returns     :
#Parameters  :   None
#Throws      :   If plex_name is not set
#                If run_id is not set
#Comments    :

sub get_and_check_options {

    GetOptions(
        \%options,
        'crispr_db=s',
        'plex_name=s',
        'run_id=s',
        'analysis_started=s',
        'analysis_finished=s',
        'sample_plate_format=s',
        'sample_plate_fill_direction=s',
        'miseq_plate_format=s',
        'miseq_plate_fill_direction=s',
        'barcode_plate_format=s',
        'barcode_plate_fill_direction=s',
        'help',
        'man',
        'debug+',
        'verbose',
    ) or pod2usage(2);

    # Documentation
    if( $options{help} ) {
        pod2usage( -verbose => 0, -exitval => 1, );
    }
    elsif( $options{man} ) {
        pod2usage( -verbose => 2 );
    }

    # check that plex_name and run_id are specified
    if( !defined $options{plex_name} ){
        my $msg = join(q{ }, "Option --plex_name is required!\n", ) . "\n";
        pod2usage( $msg );
    }
    if( !defined $options{run_id} ){
        my $msg = join(q{ }, "Option --run_id is required!\n", ) . "\n";
        pod2usage( $msg );
    }

    # default values
    $options{debug} = defined $options{debug} ? $options{debug} : 0;
    if( $options{debug} > 1 ){
        use Data::Dumper;
    }
    $options{sample_plate_format} = defined $options{sample_plate_format} ? $options{sample_plate_format} : '96';
    $options{sample_plate_fill_direction} = defined $options{sample_plate_fill_direction} ? $options{sample_plate_fill_direction} : 'row';
    $options{miseq_plate_format} = defined $options{miseq_plate_format} ? $options{miseq_plate_format} : '96';
    $options{miseq_plate_fill_direction} = defined $options{miseq_plate_fill_direction} ? $options{miseq_plate_fill_direction} : 'row';
    $options{barcode_plate_format} = defined $options{barcode_plate_format} ? $options{barcode_plate_format} : '96';
    $options{barcode_plate_fill_direction} = defined $options{barcode_plate_fill_direction} ? $options{barcode_plate_fill_direction} : 'row';

    print "Settings:\n", map { join(' - ', $_, defined $options{$_} ? $options{$_} : 'off'),"\n" } sort keys %options if $options{verbose};
}

__END__

=pod

=head1 NAME

add_samples_to_db_from_sample_manifest.pl

=head1 DESCRIPTION

Script to take a sample manifest file as input and add those samples to an SQL database.


=cut

=head1 SYNOPSIS

    add_samples_to_db_from_sample_manifest.pl [options] filename(s) | STDIN
        --crispr_db                         config file for connecting to the database
        --sample_plate_format               plate format for sample plate (96 or 384)
        --sample_plate_fill_direction       fill direction for sample plate (row or column)
        --help                              print this help message
        --man                               print the manual page
        --debug                             print debugging information
        --verbose                           turn on verbose output


=head1 ARGUMENTS

=over

=item B<input>

Sample manifest. Can be a list of filenames or on STDIN.

Should contain the following columns in this order:
barcode, plex_name, plate_num, well_id, injection_name, generation, sample_type, species

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

=back

=over

=item B<--sample_plate_format>

plate format for sample plate (96 or 384)
default: 96

=item B<--sample_plate_fill_direction>

fill direction for sample plate (row or column)
default: row

=item B<--debug>

Print debugging information.

=item B<--help>

Print a brief help message and exit.

=item B<--man>

Print this script's manual page and exit.

=back

=head1 DEPENDENCIES

Crispr

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
