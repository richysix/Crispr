#!/usr/bin/env perl

# PODNAME: add_samples_to_db_from_sample_manifest.pl
# ABSTRACT: Add information about samples to a CRISPR SQL database from a sample manifext file.

use warnings;
use strict;
use Getopt::Long;
use autodie;
use Pod::Usage;

use Crispr::DB::DBConnection;

# get options
my %options;
get_and_check_options();

# connect to db
my $db_connection = Crispr::DB::DBConnection->new( $options{crispr_db}, );

# go through input
while(<>){
    my $line = $_;
    chomp $line;
    my ( $barcode, $plex_name, $plate_num, $well_id, $injection_name,
        $generation, $sample_type, $species, ) = split /\t/, $line ;
    
    # get injection id and subplex id from db using plate_num and injection_name
    my $sql = <<'END_SQL';
    SELECT subplex_id, i.injection_id
    FROM injection i, subplex sub
    WHERE i.injection_id = sub.injection_id AND
        i.injection_name = ? AND
        sub.plate_num = ?;
END_SQL

    my $dbh = $db_connection->connection->dbh();
    
    my $sth = $dbh->prepare( $sql );
    $sth->execute( $injection_name, $plate_num, );
    
    my @results;
    while( my @fields = $sth->fetchrow_array ){
		push @results, \@fields;
	}
    if( scalar @results != 1 ){
        die "Either too many or too few results returned for:\n$line\n";
    }
    my $subplex_id = $results[0]->[0];
    my $injection_id = $results[0]->[1];
    
    my $add_sql = 'INSERT into sample values( ?, ?, ?, ?, ?, ?, ?, ?, ? );';
    
    my $sample_name = join("_", $subplex_id, $well_id, );
    $sth = $dbh->prepare( $add_sql );
    $sth->execute( undef, $sample_name, $injection_id, $subplex_id,
        $well_id, $barcode, $generation, $sample_type, $species,
    );
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