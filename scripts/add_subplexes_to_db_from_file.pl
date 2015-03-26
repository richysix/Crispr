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
use Crispr::DB::Subplex;
use Crispr::DB::Sample;
use Crispr::Plate;

# get options
my %options;
get_and_check_options();


# connect to db
my $db_connection = Crispr::DB::DBConnection->new( $options{crispr_db}, );
my $plex_adaptor = $db_connection->get_adaptor( 'plex' );
my $injection_pool_adaptor = $db_connection->get_adaptor( 'injection_pool' );
my $subplex_adaptor = $db_connection->get_adaptor( 'subplex' );
my $sample_adaptor = $db_connection->get_adaptor( 'sample' );

# make a minimal plate for parsing well-ranges
my $sample_plate = Crispr::Plate->new(
    plate_category => 'samples',
    fill_direction => $options{fill_direction},
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
my @attributes = ( qw{ subplex_id plate_num injection_name wells barcodes generation type species } );

my @required_attributes = qw{ plate_num injection_name wells barcodes generation type species };

my $comment_regex = qr/#/;
my @columns;
my @subplexes;
my @samples_for_subplex;
# go through input
while(<>){
    my @values;
    
    chomp;
    if( $INPUT_LINE_NUMBER == 1 ){
        if( !m/\A $comment_regex/xms ){
            die "Input needs a header line starting with a #";
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
    
    my $injection_pool =
        $injection_pool_adaptor->fetch_by_name( $args{injection_name} );
    
    my $subplex = Crispr::DB::Subplex->new(
        db_id => $args{subplex_id},
        plex => $plex,
        injection_pool => $injection_pool,
        plate_num => $args{plate_num},
    );
    
    push @subplexes, $subplex;
    
    # make samples for subplex
    my @samples;
    my @barcodes = parse_barcodes( $args{barcodes} );
    my @wells = parse_wells( $args{wells} );
    if( scalar @barcodes != scalar @wells ){
        die join("\n", "Number of barcodes is not the same as the number of wells",
                   $_, ), "\n"; 
    }
    
    while( @barcodes ){
        my $barcode = shift @barcodes;
        my $well = shift @wells;
        
        my $sample = Crispr::DB::Sample->new(
            db_id => undef,
            injection_pool => $injection_pool,
            subplex => $subplex,
            barcode_id => $barcode,
            generation => $args{generation},
            sample_type => $args{type},
            well_id => $well,
        );
        push @samples, $sample;
    }
    
    push @samples_for_subplex, \@samples;
}

if( $options{debug} > 1 ){
    warn Dumper( @subplexes, @samples_for_subplex );
}

for( my $i = 0; $i < scalar @subplexes; $i++ ){
    my $subplex = $subplexes[$i];
    my $samples = $samples_for_subplex[$i];
    eval{
        $subplex_adaptor->store_subplex( $subplex );
    };
    if( $EVAL_ERROR ){
        die join(q{ }, "There was a problem storing the subplex,",
                $subplex->injection_pool->injection_name, "in the database.\n",
                "ERROR MSG:", $EVAL_ERROR, ), "\n";
    }
    else{
        print join(q{ }, 'Subplex',
            'was stored correctly in the database with id:',
            $subplex->db_id,
        ), "\n";
    }
    
    eval{
        $sample_adaptor->store_samples( $samples );
    };
    if( $EVAL_ERROR ){
        die join(q{ }, "There was a problem storing one of the samples",
                "in the database.\n",
                "ERROR MSG:", $EVAL_ERROR, ), "\n";
    }
    else{
        print join("\n",
                map { join(q{ }, 'Sample:',
                            $_->sample_name,
                            'was stored correctly in the database with id:',
                            $_->db_id, ) } @{$samples},
        ), "\n";
    }
}



sub parse_barcodes {
    my ( $barcodes, ) = @_;
    my @barcodes;
    
    if( $barcodes =~ m/\A \d+ \z/xms ){
        @barcodes = ( $barcodes );
    }
    elsif( $barcodes =~ m/\A \d+       #digits
                            ,+      # zero or more commas
                            \d+     # digits
                        /xms ){
        @barcodes = split /,/, $barcodes;
    }
    elsif( $barcodes =~ m/\A \d+        # digits
                            \-          # literal hyphen
                            \d+         # digits
                            \z/xms ){
        my ( $start, $end ) = split /-/, $barcodes;
        @barcodes = ( $start .. $end );
    }
    else{
        die "Couldn't understand barcodes, $barcodes!\n";
    }
    if( $options{debug} > 1 ){
        warn "@barcodes\n";
    }
    return @barcodes;
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

sub get_and_check_options {
    
    GetOptions(
        \%options,
		'crispr_db=s',
        'plex_name=s',
        'run_id=s',
        'analysis_started=s',
        'analysis_finished=s',
        'fill_direction=s',
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
    $options{fill_direction} = defined $options{fill_direction} ? $options{fill_direction} : 'column';
    
    
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