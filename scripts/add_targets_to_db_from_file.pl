#!/usr/bin/env perl

# PODNAME: add_targets_to_db_from_file.pl
# ABSTRACT: Add target info into CRISPR SQL database.

use warnings; use strict;
use autodie;
use Pod::Usage;
use Getopt::Long;
use List::MoreUtils qw{ any };
use English qw( -no_match_vars );

use Crispr::Target;
use Crispr::DB::DBConnection;
use Crispr::DB::TargetAdaptor;
use Crispr::Config;

my ( $dbhost, $dbport, $dbuser, $dbpass );
my $comment_regex = qr/#/;

# Get and check command line options
my %options;
get_and_check_options();

# connect to db
my $DB_connection = Crispr::DB::DBConnection->new( $options{crispr_db}, );

# get Target Adaptor using database adaptor
my $target_adaptor = $DB_connection->get_adaptor( 'target' );

my @attributes = qw{ target_id target_name assembly chr start end strand
    species requires_enzyme gene_id gene_name requestor ensembl_version
    designed };

my @required_attributes = qw{ target_name start end strand requires_enzyme
    requestor };

my @columns;
my @targets;
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
            if( !any { $column_name eq $_ } @attributes ){
                die "Could not recognise column name, ", $column_name, ".\n";
            }
        }
        foreach my $attribute ( @required_attributes ){
            if( !any { $attribute eq $_ } @columns ){
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
    
    my $target = Crispr::Target->new( \%args );
    warn join("\t", $target->info ), "\n" if $options{debug};
    
    push @targets, $target;
}

eval{
    $target_adaptor->store_targets( \@targets );
};
if( $EVAL_ERROR ){
    warn "There was a problem storing one of the targets in the database.\n",
            "ERROR MSG:", $EVAL_ERROR, "\n";
}
else{
    foreach ( @targets ){
        print join(q{ }, join(q{}, 'ID=', $_->target_id, ':', ), "Target", $_->target_name, "was successfully added to the database.\n", );
    }
}

sub get_and_check_options {
    GetOptions(
        \%options,
        'crispr_db=s',
        'debug',
        'help',
        'man',
    ) or pod2usage(2);
    
    # Documentation
    if( $options{help} ) {
        pod2usage( -verbose => 0, -exitval => 1, );
    }
    elsif( $options{man} ) {
        pod2usage( -verbose => 2 );
    }
    
    if( !defined $options{crispr_db} ){
        pod2usage("option --crispr_db must be set!\n");
    }
    if( !defined $options{debug} ){
        $options{debug} = 0;
    }
    return 1;
}

__END__

=pod

=head1 NAME

add_targets_to_db_from_file.pl

=head1 DESCRIPTION

Takes Information on crispr target region and enters it into a MySQL or SQLite database.

=head1 SYNOPSIS

    add_targets_to_db_from_file.pl [options] filename(s) | target info on STDIN
        --crispr_db             config file for connecting to the database
        --help                  prints help message and exits
        --man                   prints manual page and exits
        --debug                 prints debugging information

=head1 REQUIRED ARGUMENTS

=over

=item B<input_file(s)>

Tab-separated information on CRISPR target regions to add to an instance of a MySQL/SQLite database.

It must contain a header line (starting with #) and should contain the following columns: 
target_name start end strand requires_enzyme requestor

Optional columns are:
target_id assembly chr species gene_id gene_name ensembl_version designed

=back

=head1 OPTIONS

=over 8

=item B<--crispr_db>

Database config file containing tab-separated key value pairs.
keys are:

=over

=item driver

mysql or sqlite

=item host

database host name (MySQL only)

=item port

database port (MySQL only)

=item user

database username (MySQL only)

=item pass

database password (MySQL only)

=item dbname

name of the database

=item dbfile

path to database file (SQLite only)

=back

## NOT CURRENTLY IMPLEMENTED  ##
The values can also be set as environment variables.
At the moment MySQL is assumed as the driver for this.

=over

=item MYSQL_HOST

=item MYSQL_PORT

=item MYSQL_USER

=item MYSQL_PASS

=item MYSQL_DBNAME

=back

At least $MYSQL_USER, $MYSQL_PASS and $MYSQL_DBNAME need to be set.
$MYSQL_HOST will default to 127.0.0.1 if not set.
$MYSQL_PORT will default to 3306.

=back

=head1 AUTHOR

Richard White

richard.white@sanger.ac.uk

=cut

