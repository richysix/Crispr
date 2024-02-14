#!/usr/bin/env perl
# crispr.t
use warnings;
use strict;

my $chr;
my $offset = 1;
my $strand;
while(<>) {
    chomp;
    if (m/\A >/xms) {
        $chr = $_;
        $chr =~ s/\A >//xms;
        $offset = 1;
    } else {
        my $len = length($_);
        $strand = "1";
        while (m/(?=([ACGT]{21}GG))/xmsg) {
            my $start = $offset + pos($_);
            my $end = $start + 22;
            my $name = join(":", $chr, join("-", $start, $end), $strand);
            my $protospacer_seq = substr($1, 0, 20);
            print join("\t", $name, $chr, $start, $end, $strand, $1, $protospacer_seq), "\n";
        }
        $strand = "-1";
        while (m/(?=(CC[ACGT]{21}))/xmsg) {
            my $start = $offset + pos($_);
            my $end = $start + 22;
            my $name = join(":", $chr, join("-", $start, $end), $strand);
            my $guide_seq = reverse($1);
            $guide_seq =~ tr/ACGT/TGCA/;
            my $protospacer_seq = substr($guide_seq, 0, 20);
            print join("\t", $name, $chr, $start, $end, $strand, $guide_seq, $protospacer_seq), "\n";
        }
        $offset += $len;
    }
}