#!/usr/bin/env perl

# PODNAME: program_name.pl
# ABSTRACT: Description

use warnings;
use strict;
use Getopt::Long;
use autodie;
use Pod::Usage;

use Bio::SeqIO;
use DateTime;

# get options
my %options;
get_and_check_options();

if ($options{debug}) {
    warn "all crisprs start: ", DateTime->now()->hms(), "\n";
}
my $file = $ARGV[0];
my $seq_in = Bio::SeqIO->new(-file   => "$file",
                            -format => 'fasta', );

my $crispr_regex_f = qr/(?=([ACGTacgt]{21}[Gg][Gg]))/xms;
my $crispr_regex_r = qr/(?<=([Cc][Cc][ACGTacgt]{21}))/xms;

my $outfile = $ARGV[1];
open my $out_fh, '>', $outfile;
while ( my $seq = $seq_in->next_seq() ) {
    if ($options{debug} > 0) {
        warn "Chr: ", $seq->display_id, "\n";
    }
    my $search_seq = $seq->seq;
    #my $i = 1;
    while( $search_seq =~ m/$crispr_regex_f/g ){
        my $match_offset = pos($search_seq);
        my $name = join(":", $seq->display_id, join("-", $match_offset + 1, $match_offset + 23), "1");
        my $seq_upper = uc($1);
        my $comp_seq = substr($seq_upper, 0, 20);
        print {$out_fh} join("\t", $name, $seq->display_id, $match_offset + 1,
                             $match_offset + 23, "1", $seq_upper, $comp_seq), "\n";
        #last if $i >= 5;
        #$i++;
    }
    #$i = 1;
    $search_seq = $seq->seq;
    while( $search_seq =~ m/$crispr_regex_r/g ){
        my $match_offset = pos($search_seq);
        my $name = join(":", $seq->display_id, join("-", $match_offset - 22, $match_offset), "-1");
        my $seq_upper = uc($1);
        my $rev_comp = scalar reverse $seq_upper;
        $rev_comp =~ tr/[ACGT]/[TGCA]/;
        my $comp_seq = substr($rev_comp, 0, 20);
        print {$out_fh} join("\t", $name, $seq->display_id, $match_offset - 22,
                             $match_offset, "-1", $seq_upper, $comp_seq, ), "\n";
        #last if $i >= 5;
        #$i++;
    }
}
close($out_fh);
if ($options{debug}) {
    warn "all crisprs end: ", DateTime->now()->hms(), "\n";
}

my $test_string = 'GACTACTGTAATGAGTTACT';

# go through file and check hamming distance
if ($options{debug}) {
    warn "hamming dist start: ", DateTime->now()->hms(), "\n";
}
open my $in_fh, '<', $outfile;
while(my $line = <$in_fh>) {
    chomp $line;
    my ($name, $chr, $start, $end, $strand, $seq_upper, $comp_seq, ) = split /\t/, $line;
    warn $line if(!defined $comp_seq);
    if (hamming_distance($test_string, $comp_seq) <= 1) {
        print join("\t", $test_string, $comp_seq, hamming_distance($test_string, $comp_seq), $seq_upper), "\n";
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

    program_name.pl [options] genome_file output_file
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

This software is Copyright (c) 2022. Queen Mary University of London.

This is free software, licensed under:

  The GNU General Public License, Version 3, June 2007

=cut