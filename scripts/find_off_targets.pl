#!/usr/bin/env perl

# PODNAME: program_name.pl
# ABSTRACT: Description

use warnings;
use strict;
use Getopt::Long;
use autodie;
use Pod::Usage;
use DateTime;

# get options
my %options;
get_and_check_options();

my $crisprs_file = $ARGV[0];
my $crispr_seq = $ARGV[1];
my $protospacer_seq;
if (length($crispr_seq) == 23) {
    $protospacer_seq = substr($crispr_seq, 0, 20);
} else {
    $protospacer_seq = $crispr_seq;
}

# go through file and check hamming distance
if ($options{debug}) {
    warn "hamming dist start: ", DateTime->now()->hms(), "\n";
}
open my $in_fh, '<', $crisprs_file;
while(my $line = <$in_fh>) {
    chomp $line;
    my ($name, $chr, $start, $end, $strand, $seq_upper, $comp_seq, ) = split /\t/, $line;
    warn $line if(!defined $comp_seq);
    if (hamming_distance($protospacer_seq, $comp_seq) <= $options{'threshold'}) {
        print join("\t", $name, $chr, $start, $end, $strand, $seq_upper,
                   $comp_seq, $protospacer_seq, hamming_distance($protospacer_seq, $comp_seq), ), "\n";
    }
}
if ($options{debug}) {
    warn "hamming dist end: ", DateTime->now()->hms(), "\n";
}


################################################################################
# SUBROUTINES

# hamming_distance
#
#  Usage       : hamming_distance($string1, $string2)
#  Purpose     : Return the hamming distance between two strings assuming they
#                are the same length
#  Returns     : Hamming Distance (Int)
#  Parameters  : string1 Str
#                string2 Str
#  Throws      : 
#  Comments    : None

sub hamming_distance {
    return ($_[0] ^ $_[1]) =~ tr/\001-\255//;
}

#get_and_check_options
#
#  Usage       : get_and_check_options()
#  Purpose     : parse the options supplied to the script using GetOpt::Long
#  Returns     : None
#  Parameters  : None
#  Throws      : 
#  Comments    : The default option are
#                help which print a SYNOPSIS
#                man which prints the full man page
#                debug
#                verbose

sub get_and_check_options {
    
    GetOptions(
        \%options,
        'threshold=i',
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
    
    $options{'threshold'} = $options{'threshold'} ? $options{'threshold'} : 4;
    
    $options{debug} = $options{debug} ? $options{debug} : 0;
    print "Settings:\n", map { join(' - ', $_, defined $options{$_} ? $options{$_} : 'off'),"\n" } sort keys %options if $options{verbose};
}

__END__

=pod

=head1 NAME

program_name.pl

=head1 DESCRIPTION

Description

=cut

=head1 SYNOPSIS

    program_name.pl [options] all_crisprs_file sequence
        --help                  print this help message
        --man                   print the manual page
        --debug                 print debugging information
        --verbose               turn on verbose output


=head1 ARGUMENTS

=over

arguments

=back

=head1 OPTIONS

**Same for optional arguments.

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

Richard White <rich@buschlab.org>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2020. University of Cambridge.

This is free software, licensed under:

  The GNU General Public License, Version 3, June 2007

=cut