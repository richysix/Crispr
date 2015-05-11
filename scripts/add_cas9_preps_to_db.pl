#!/usr/bin/env perl

# PODNAME: add_cas9_prep_to_db.pl
# ABSTRACT: Add information about a Cas9 RNA prep into CRISPR SQL database.

use warnings;
use strict;
use Getopt::Long;
use autodie;
use Pod::Usage;
use English qw( -no_match_vars );
use List::MoreUtils qw( any none );

use Crispr::Cas9;
use Crispr::DB::Cas9Prep;
use Crispr::DB::DBConnection;
use Crispr::DB::Cas9PrepAdaptor;

# get options
my %options;
get_and_check_options();

# connect to db
my $db_connection = Crispr::DB::DBConnection->new( $options{crispr_db}, );
my $cas9_prep_adaptor = $db_connection->get_adaptor( 'cas9_prep' );

# parse input file/options and create Cas9Prep objects
my @attributes = ( qw{ db_id name species vector type notes prep_type made_by date } );

my @required_attributes = qw{ name prep_type made_by date };

my $comment_regex = qr/#/;
my @columns;
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
    
    my %cas9_args = (
        name => $args{name},
    );
    if( $args{species} ){ $cas9_args{species} = $args{species}; }
    if( $args{vector} ){ $cas9_args{vector} = $args{vector}; }
    if( $args{type} ){ $cas9_args{type} = $args{type}; }
    if( $args{db_id} ){ $cas9_args{name} = $args{name}; }
    # make new Cas9 object
    my $cas9 = Crispr::Cas9->new( \%cas9_args );
    
    my %cas9_prep_args = (
        cas9 => $cas9,
        prep_type => $args{prep_type},
        made_by => $args{made_by},
        date => $args{date},
    );
    if( $args{notes} ){ $cas9_prep_args{notes} = $args{notes}; }
    if( $args{db_id} ){ $cas9_prep_args{db_id} = $args{db_id}; }
    
    # make new Cas9Prep object
    my $cas9_prep = Crispr::DB::Cas9Prep->new( \%cas9_prep_args, );
    
    # store Cas9Prep in db
    $cas9_prep_adaptor->store( $cas9_prep, );
    
    print "Cas9 prep, ", $_, ", was stored correctly in the database with id: ",
        $cas9_prep->db_id, "\n";
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
    
    # default settings
    $options{debug} = $options{debug}   ?   $options{debug} :   0;
    
    print "Settings:\n", map { join(' - ', $_, defined $options{$_} ? $options{$_} : 'off'),"\n" } sort keys %options if $options{verbose};
}

__END__

=pod

=head1 NAME

add_cas9_prep_to_db.pl

=head1 DESCRIPTION

Script to add information about a Cas9 RNA prep to an SQL database.
The information required is detailed below in input

=head1 SYNOPSIS

    add_cas9_prep_to_db.pl [options] input file | STDIN
        --crispr_db             config file for connecting to the database
        --help                  print this help message
        --man                   print the manual page
        --debug                 print debugging information
        --verbose               turn on verbose output


=head1 ARGUMENTS

=over

=item B<input>

Information on Cas9 preps.
There must be a header line beginning with #.
Should contain the following columns:
cas9_type prep_type made_by date

Optional columns are:

=over

=item species - default 'zebrafish'

=item target_seq - default N20
target_seq does not include the PAM.

=item PAM - default NGG

=item name - default pCS2_ZfnCas9n_Chen

=item notes - NULL

=back

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