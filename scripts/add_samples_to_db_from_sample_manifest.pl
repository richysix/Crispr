#!/usr/bin/env perl

# PODNAME: add_samples_to_db_from_sample_manifest.pl
# ABSTRACT: Add information about samples to a CRISPR SQL database from a sample manifext file.

use warnings;
use strict;
use Getopt::Long;
use autodie;
use Pod::Usage;
use English qw( -no_match_vars );
use List::MoreUtils qw( none );

use Crispr::DB::DBConnection;
use Crispr::DB::Sample;

# get options
my %options;
get_and_check_options();

# connect to db
my $db_connection = Crispr::DB::DBConnection->new( $options{crispr_db}, );
my $injection_pool_adaptor = $db_connection->get_adaptor( 'injection_pool' );
my $sample_adaptor = $db_connection->get_adaptor( 'sample' );

# parse input file, create Sample objects and add them to db
my @attributes = ( qw{ injection_name num_samples generation sample_type species } );

my @required_attributes = qw{ injection_name num_samples generation sample_type species };

my $comment_regex = qr/#/;
my @columns;
my @samples;
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
    my $samples = $sample_adaptor->fetch_all_by_injection_pool( $args{'injection_pool'} );
    
    my @sample_numbers;
    if( @{$samples} ){
        @sample_numbers = sort { $b <=> $a }
                            map { $_->sample_number } @{$samples};
    }
    my $starting_sample_number = @sample_numbers
        ?   $sample_numbers[0]
        :   0;
    
    foreach my $sample_number ( $starting_sample_number + 1 .. $starting_sample_number + $args{'num_samples'} ){
        # make new sample object
        $args{'sample_name'} = join("_", $args{'injection_name'}, $sample_number, );
        $args{'sample_number'} = $sample_number;
        my $sample = Crispr::DB::Sample->new( \%args );
        push @samples, $sample;
    }
}

if( $options{debug} > 1 ){
    warn Dumper( @samples, );
}

foreach my $sample ( @samples ){
    eval{
        $sample_adaptor->store_sample( $sample );
    };
    if( $EVAL_ERROR ){
        die join(q{ }, "There was a problem storing the sample,",
                $sample->sample_name, "in the database.\n",
                "ERROR MSG:", $EVAL_ERROR, ), "\n";
    }
    else{
        print join(q{ }, 'Sample,', $sample->sample_name . ',',
            'was stored correctly in the database with id:',
            $sample->db_id,
        ), "\n";
    }
}

sub get_and_check_options {
    
    GetOptions(
        \%options,
		'crispr_db=s',
        'help',
        'man',
        'debug+',
        'verbose',
    ) or pod2usage(2);
    
    # Documentation
    if( $options{help} ) {
        pod2usage(1);
    }
    elsif( $options{man} ) {
        pod2usage( -verbose => 2 );
    }
    
    # default values
    $options{debug} = defined $options{debug} ? $options{debug} : 0;
    if( $options{debug} > 1 ){
        use Data::Dumper;
    }
    
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
        --crispr_db             config file for connecting to the database
        --help                  print this help message
        --man                   print the manual page
        --debug                 print debugging information
        --verbose               turn on verbose output


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