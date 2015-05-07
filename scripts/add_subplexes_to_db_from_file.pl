#!/usr/bin/env perl

# PODNAME: add_subplexes_to_db_from_file.pl
# ABSTRACT: Add information about subplexes and samples to a CRISPR SQL database from a file.

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

if( $options{debug} > 1 ){
    warn Dumper( $plex );
}

# parse input file, create Subplex and Sample objects and add them to db
my @attributes = ( qw{ sample_plate_num injection_name sample_numbers wells barcodes barcode_plate_num amplicons } );

my @required_attributes = qw{ sample_plate_num injection_name sample_numbers wells amplicons };

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
        # check that one of barcodes or barcode_plate_num is present
        if( scalar ( grep { $_ eq 'barcodes' } @columns ) == 0 &&
            scalar ( grep { $_ eq 'barcode_plate_num' } @columns ) == 0 ){
            die "One of the columns must be either barcodes or barcode_plate_num.\n";
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
            push @primer_pairs, $primer_pair;
        }
        else{
            push @primer_pairs, $primer_pair_cache{$amplicon_info};
        }
    }

    my @well_ids = parse_wells( $args{wells} );
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
    
    if( scalar @barcodes != scalar @well_ids ){
        die join("\n", "Number of barcodes is not the same as the number of wells",
                   $_, ), "\n"; 
    }
    
    # got through barcodes and sample wells and fetch samples from db
    # make sample_amplicon objects and add to array
    my @sample_numbers = parse_sample_numbers( $args{ 'sample_numbers' } );    
    my @sample_amplicons;
    while( @barcodes ){
        my $barcode_id = shift @barcodes;
        my $well_id = shift @well_ids;
        my $sample_number = shift @sample_numbers;
        my $sample_name = join("_", $args{'injection_name'}, $sample_number, );
        my $sample = $sample_adaptor->fetch_by_name( $sample_name, );
        my $sample_amplicon = Crispr::DB::SampleAmplicon->new(
            sample => $sample,
            amplicons => \@primer_pairs,
            barcode_id => $barcode_id,
            plate_number => $args{'sample_plate_num'},
            well_id => $well_id,
        );
        push @sample_amplicons, $sample_amplicon;
    }
    
    # make new analysis object
    my $analysis = Crispr::DB::Analysis->new(
        plex => $plex,
        analysis_started => $options{analysis_started},
        analysis_finished => $options{analysis_finished},
        info => \@sample_amplicons,
    );
    push @analyses, $analysis;
}

if( $options{debug} > 1 ){
    warn Dumper( @analyses );
}

# store analyses in db
eval{
    $analysis_adaptor->store_analyses( \@analyses );
};
if( $EVAL_ERROR ){
    die join(q{ }, "There was a problem storing one of the analyses, in the database.\n",
            "ERROR MSG:", $EVAL_ERROR, ), "\n";
}
else{
    print join("\n", 
        map { join(q{ },
                'Analysis was stored correctly in the database with id:',
                $_->db_id, ); } @analyses,
    ), "\n";
}

sub parse_barcodes {
    my ( $barcodes, ) = @_;
    my @barcodes = parse_number_range( $barcodes, 'barcodes' );
    if( $options{debug} > 1 ){
        warn "@barcodes\n";
    }
    return @barcodes;
}

sub parse_sample_numbers {
    my ( $sample_numbers, ) = @_;
    my @sample_numbers = parse_number_range( $sample_numbers, 'sample numbers' );
    if( $options{debug} > 1 ){
        warn "@sample_numbers\n";
    }
    return @sample_numbers;
}

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

sub parse_wells {
    my ( $wells, ) = @_;
    my @wells;
    if( $wells =~ m/\A [A-P]\d+             # single well
                        \z/xms ){
        @wells = ( $wells );
    }
    elsif( $wells =~ m/\A [A-P]\d+          # well_id
                            ,+              # zero or more commas
                            [A-P]\d+        # well_id
                        /xms ){
        @wells = split /,/, $wells;
    }
    elsif( $wells =~ m/\A  [A-P]\d+         # well_id
                            \-              # literal hyphen
                            [A-P]\d+        # well_id
                        \z/xms ){
        @wells = $sample_plate->range_to_well_ids( $wells );
    }
    else{
        die "Couldn't understand wells, $wells!\n";
    }
    if( $options{debug} > 1 ){
        warn "@wells\n";
    }
    return @wells;
}

=func
Usage       :   my @barcode_plates = slices_to_chunk( $slices, 1, 100 );
Purpose     :   Produce and return an Array of barcode plates for assigning
                barcode indexes to samples
Returns     :   Arrayref of Labware::Plate objects
Parameters  :   None
Throws      :   
Comments    :   Assumes there are 384 barcodes.
                It will produce 4 x 96 well plates or 1 x 384 well plate
                depending on the barcode plate format
=cut

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
    $options{barcode_plate_format} = defined $options{barcode_plate_format} ? $options{barcode_plate_format} : '96';
    $options{barcode_plate_fill_direction} = defined $options{barcode_plate_fill_direction} ? $options{barcode_plate_fill_direction} : 'row';
    
    print "Settings:\n", map { join(' - ', $_, defined $options{$_} ? $options{$_} : 'off'),"\n" } sort keys %options if $options{verbose};
}

__END__

=pod

=head1 NAME

add_subplexes_to_db_from_file.pl

=head1 DESCRIPTION

Script to add information abotu sequencing subplexes (a subset of a full run) to a CRISPR SQL database.


=cut

=head1 SYNOPSIS

    add_subplexes_to_db_from_file.pl [options] filename(s) | STDIN
        --plex_name             name of the plex (e.g. MPX22) REQUIRED
        --run_id                The id of the sequencing run REQUIRED
        --analysis_started      date that analysis was started (yyyy-mm-dd)
        --analysis_finished     date that analysis was finished (yyyy-mm-dd)
        --crispr_db             config file for connecting to the database
        --help                  print this help message
        --man                   print the manual page
        --debug                 print debugging information
        --verbose               turn on verbose output


=head1 ARGUMENTS

=over

=item B<input>

Subplex info. Can be a list of filenames or on STDIN.

Should contain the following columns: 

=back

=head1 OPTIONS

=over 8

=item B<--plex_name Str>

Name of the plex that the subplexes are a part of. Str (e.g. mpx22)
This is REQUIRED.

=item B<--run_id Int>

The id of the sequencing run for the plex
This is REQUIRED.

=item B<--analysis_started Date>

date that analysis was started (yyyy-mm-dd)

=item B<--analysis_finished Date>

date that analysis was finished (yyyy-mm-dd)

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

=item B<--debug>

Print debugging information.

=item B<--help>

Print a brief help message and exit.

=item B<--man>

Print this script's manual page and exit.

=back

=head1 DEPENDENCIES

None

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