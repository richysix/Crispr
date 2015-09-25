#!/usr/bin/env perl

# PODNAME: filter_fastq.pl
# ABSTRACT: Filter FASTQ files removing reads shorter than a certain distance.

use warnings; use strict;
use Getopt::Long;
use autodie;
use Pod::Usage;

my %options;
get_and_check_options();

my %fhs;
my %out_fhs;
my $in_file;
if( $options{interleaved} ){
    my $fastq_file = shift @ARGV;
    $in_file = $fastq_file;
    open my $fh, '<', $fastq_file;
    $fhs{1} = $fh;
    $fhs{2} = $fh;
    if( $options{out} ){
        my $out_file = $options{out};
        open my $out_fh, '>', $out_file;
        $out_fhs{1} = $out_fh;
        $out_fhs{2} = $out_fh;
    }
    elsif( $options{out1} && $options{out2} ){
        my $read1_out_file = $options{out1};
        my $read2_out_file = $options{out2};
        open my $out_fh1, '>', $read1_out_file;
        open my $out_fh2, '>', $read2_out_file;
        $out_fhs{1} = $out_fh1;
        $out_fhs{2} = $out_fh2;
    }
    else{
        my $out_file = $fastq_file;
        $out_file =~ s/\.fastq/.filt.fastq/xms;
        open my $out_fh, '>', $out_file;
        $out_fhs{1} = $out_fh;
        $out_fhs{2} = $out_fh;
    }
}
elsif( $options{read1} && $options{read2} ){
    my $read1_file = $options{read1};
    $in_file = $read1_file;
    open my $fh1, '<', $read1_file;
    $fhs{1} = $fh1;
    my $read1_out_file;
    if( $options{out1} ){
        $read1_out_file = $options{out1};
    }
    else{
        $read1_out_file = $read1_file;
        $read1_out_file =~ s/\.fastq/.filt.fastq/xms;
    }
    open my $out_fh1, '>', $read1_out_file;
    $out_fhs{1} = $out_fh1;
    
    my $read2_file = $options{read2};
    open my $fh2, '<', $read2_file;
    $fhs{2} = $fh2;
    my $read2_out_file;
    if( $options{out2} ){
        $read2_out_file = $options{out2};
    }
    else{
        $read2_out_file = $read2_file;
        $read2_out_file =~ s/\.fastq/.filt.fastq/xms;
    }
    open my $out_fh2, '>', $read2_out_file;
    $out_fhs{2} = $out_fh2;    
}
else{
    die "Could not understand options!\n";
}

my @read1_lines = get_next_lines( 1 );
my @read2_lines = get_next_lines( 2 );
my ( $in_rp, $out_rp ) = ( 0, 0 );

while( defined $read1_lines[0] ){
    $in_rp++;
    my $print = 1;
    # check lines have matching ids
    my $read1_id = $read1_lines[0];
    $read1_id =~ s|/1||xms;
    my $read2_id = $read2_lines[0];
    $read2_id =~ s|/2||xms;
    if( $read1_id ne $read2_id ){
        die join("\n", "Read names don't match!", $read1_lines[0], $read2_lines[0], ), "\n";
    }
    else{
        if( length $read1_lines[1] < $options{length_threshold} || length $read2_lines[1] < $options{length_threshold} ){
            $print = 0;
        }
        if( $print ){
            $out_rp++;
            print {$out_fhs{1}} @read1_lines;
            print {$out_fhs{2}} @read2_lines;
        }
    }
    
    # get next set of reads
    @read1_lines = get_next_lines( 1 );
    @read2_lines = get_next_lines( 2 );
}

if( $out_rp > $in_rp ){
    die "$in_file: Output count is larger than input count!\n";
}
else{
    warn join("\t", "$in_file", join(": ", "Input read pairs", $in_rp ),
                join(": ", "Output read pairs", $out_rp ), ), "\n";
}

sub get_next_lines {
    my ( $read_num, ) = @_;
    my @lines;
    my $fh = $fhs{$read_num};
    foreach( 1..4 ){
        my $line = <$fh>;
        push @lines, $line;
    }
    return @lines;
}

sub get_and_check_options {
    
    GetOptions(
        \%options,
        'interleaved',
        'read1=s',
        'read2=s',
        'out=s',
        'out1=s',
        'out2=s',
        'length_threshold=i',
        'help',
        'man',
        'debug+',
        'verbose',
    ) or pod2usage(2);
    
    # Documentation
    if( $options{help} ) {
        pod2usage( -verbose => 0, exitval => 1, );
    }
    elsif( $options{man} ) {
        pod2usage( -verbose => 2 );
    }
    
    if( !exists $options{interleaved} ){
        if( !exists $options{1} || !exists $options{2} ){
            my $message = "Both of --1 and --2 must be set if --interleaved is not.\n";
            pod2usage( $message );
        }
    }
    
    # set defaults
    if( !$options{length_threshold} ){
        $options{length_threshold} = 40;
    }
}

__END__

=pod

=head1 NAME

filter_fastq.pl

=head1 DESCRIPTION

Filter FASTQ files removing reads shorter than a certain distance.
It can process single FASTQ files, interleaved FASTQ files (where paired-reads are are sequential in the file)
and paired-reads in two separate files. It can produce either a single file or two files for paired-end reads.

=cut

=head1 SYNOPSIS

    filter_fastq.pl [options] input fastq file
        --length_threshold              threshold below which to remove read pairs  [Default: 40]
        --interleaved                   input fastq file is interleaved (output will be interleaved unless both of --out1 and --out2 are specified)
        --read1                         read1 fastq file
        --read2                         read2 fastq file
        --out                           interleaved output file
        --out1                          read1 output file
        --out2                          read2 output file
        --help                          prints help message and exits
        --man                           prints manual page and exits
        --debug                         prints debugging information
        --verbose                       prints logging information



=head1 ARGUMENTS

=over

=item B<input file>

Name of the FASTQ file to filter. If the reads are in two separate files then supply them using --read1 and --read2 options.

=back

=head1 OPTIONS

=over

=item B<--length_threshold>

Length threshold below which to remove read pairs  [Default: 40]

=item B<--interleaved>

An interleaved FASTQ file has paired-reads in sequential records

e.g.
@read1-1
GATAGATAGGACAGATAGCAGATACGATGACGATGGAGAGTCAGGATACCCACAAATATAGGACATAGACTACGA
+
ABBBBCDDDDBBDDDDDDCACDCCCCCCCCDDDDDDDBBBBBBBCCCCDCDCDDCDCDCDCDDCDCDDDDDDBBB
@read1-2
GATAGATAGGACAGATAGCAGATACGATGACGATGGAGAGTCAGGATACCCACAAATATAGGACATAGACTACGA
+
ABBBBCDDDDBBDDDDDDCACDCCCCCCCCDDDDDDDBBBBBBBCCCCDCDCDDCDCDCDCDDCDCDDDDDDBBB

If your FASTQ file is like this, set --interleaved.
The output file will be interleaved unless both of --out1 and --out2 are specified.

=item B<--read1>

FASTQ file for the first reads of paired-reads

=item B<--read2>

FASTQ file for the second reads of paired-reads

=item B<--out>

Name for the output file. If this is not set the output file is named filename.filt.fastq where the input file is named filename.fastq

=item B<--out1>

Read1 output file

=item B<--out2>

Read2 output file

=item B<--debug>

Print debugging information.

=item B<--help>

Print a brief help message and exit.

=item B<--man>

Print this script's manual page and exit.

=back

=head1 AUTHOR

=over 4

=item *

Richard White <richard.white@sanger.ac.uk>

=back

=head1 COPYRIGHT AND LICENSE

This software is Copyright (c) 2014,2015 by Genome Research Ltd.

This is free software, licensed under:

  The GNU General Public License, Version 3, June 2007

=cut
