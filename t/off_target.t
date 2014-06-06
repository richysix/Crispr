#!/usr/bin/env perl
# off_target.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use Getopt::Long;

my $test_data = 't/data/test_targets_plus_crRNAs_plus_coding_scores.txt';
GetOptions(
    'test_data=s' => \$test_data,
);

my $count_output = qx/wc -l $test_data/;
chomp $count_output;
$count_output =~ s/\s$test_data//mxs;

plan tests => 1 + 27 + 15 + 13 + 4 + $count_output * 9;

use Crispr::OffTarget;

my $off_target = Crispr::OffTarget->new();

# check crRNA and attributes
# 1 test
isa_ok( $off_target, 'Crispr::OffTarget' );

# check method calls 27 tests
my @methods = qw( crRNA_name seed_exon_alignments number_seed_intron_hits number_seed_nongenic_hits exonerate_exon_alignments
    number_exonerate_intron_hits number_exonerate_nongenic_hits info seed_hits number_seed_exon_hits
    increment_seed_intron_hits increment_seed_nongenic_hits seed_score exonerate_hits number_exonerate_exon_hits
    increment_exonerate_intron_hits increment_exonerate_nongenic_hits exonerate_score score bwa_exon_alignments
    number_bwa_intron_hits number_bwa_nongenic_hits bwa_hits number_bwa_exon_hits increment_bwa_intron_hits
    increment_bwa_nongenic_hits bwa_score
);

foreach my $method ( @methods ) {
    can_ok( $off_target, $method );
}

my $off_target = Crispr::OffTarget->new(
    crRNA_name => 'crRNA:1:10000-10022:1',
    number_seed_intron_hits => 4,
    number_seed_nongenic_hits => 8,
    seed_exon_alignments => [ qw( 10:200-222:1 18:505-507:-1 ) ],
    number_exonerate_intron_hits => 4,
    number_exonerate_nongenic_hits => 8,
    exonerate_exon_alignments => [ qw( 5:200-222:1 9:505-507:-1 ) ],
    off_target_method => 'exonerate',
);

# test attributes - 15 tests
is( $off_target->crRNA_name, 'crRNA:1:10000-10022:1', "name 1" );
throws_ok{ $off_target->crRNA_name('crRNA:1:10020-10042:1') } qr/read-only/, 'Read-only name throws ok';
is( abs($off_target->seed_score - 0.279 ) < 0.001, 1, "score - seed");
is( $off_target->number_seed_exon_hits, 2, "num seed exon hits - 1");
is( $off_target->number_seed_intron_hits, 4, "num seed intron hits - 1");
is( $off_target->number_seed_nongenic_hits, 8, "num seed nongenic hits - 1");
is( ref $off_target->seed_exon_alignments, ARRAY, "class of seed alignments - 1");
is( join(',', @{ $off_target->seed_exon_alignments }), '10:200-222:1,18:505-507:-1', "seed exon alignments - 1");

is( abs($off_target->exonerate_score - 0.279 ) < 0.001, 1, "exonerate score");
is( $off_target->number_exonerate_exon_hits, 2, "num exo exon hits - 1");
is( $off_target->number_exonerate_intron_hits, 4, "num exo intron hits - 1");
is( $off_target->number_exonerate_nongenic_hits, 8, "num exo nongenic hits - 1");
is( ref $off_target->exonerate_exon_alignments, ARRAY, "class of mismatch alignments - 1");
is( join(',', @{ $off_target->exonerate_exon_alignments }), '5:200-222:1,9:505-507:-1', "mismatch alignments - 1");

is( abs($off_target->score - 0.078 ) < 0.001, 1, "score - overall 1");

my $off_target_2 = Crispr::OffTarget->new(
    crRNA_name => 'crRNA:1:10000-10022:1',
    off_target_method => 'exonerate',
);

# incrementing hits - 13
is( $off_target_2->number_seed_exon_hits, undef, "initial num seed exon hits - 2");
$off_target_2->seed_exon_alignments( '17:403-425:-1,10:103-425:1' );
is( $off_target_2->number_seed_exon_hits, 2, "num seed exon hits - 2");
is( join(',', @{$off_target_2->seed_exon_alignments}), '17:403-425:-1,10:103-425:1', 'seed alignments 2');
$off_target_2->increment_seed_intron_hits;
$off_target_2->increment_seed_intron_hits;
is( $off_target_2->number_seed_intron_hits, 2, "num seed intron hits - 2");
$off_target_2->increment_seed_nongenic_hits;
$off_target_2->increment_seed_nongenic_hits;
$off_target_2->increment_seed_nongenic_hits;
$off_target_2->increment_seed_nongenic_hits;
is( $off_target_2->number_seed_nongenic_hits, 4, "num seed nongenic hits - 2");
#print join("\t", $off_target_2->number_seed_exon_hits, $off_target_2->number_seed_intron_hits, $off_target_2->number_seed_nongenic_hits, $off_target_2->seed_score, ), "\n";
is( abs($off_target_2->seed_score - 0.422 ) < 0.001, 1, "score - seed 2");

is( $off_target_2->number_exonerate_exon_hits, undef, "initial num exo exon hits - 2");
$off_target_2->exonerate_exon_alignments( '17:403-425:-1' );
is( $off_target_2->number_exonerate_exon_hits, 1, "num exo exon hits - 2");
is( join(',', @{$off_target_2->exonerate_exon_alignments}), '17:403-425:-1', 'exo alignments 2');
$off_target_2->increment_exonerate_intron_hits;
$off_target_2->increment_exonerate_intron_hits;
is( $off_target_2->number_exonerate_intron_hits, 2, "num exo intron hits - 2");
$off_target_2->increment_exonerate_nongenic_hits;
$off_target_2->increment_exonerate_nongenic_hits;
$off_target_2->increment_exonerate_nongenic_hits;
$off_target_2->increment_exonerate_nongenic_hits;
is( $off_target_2->number_exonerate_nongenic_hits, 4, "num exo nongenic hits - 2");
is( abs($off_target_2->exonerate_score - 0.528 ) < 0.001, 1, "score - exo 2");

is( abs($off_target_2->score - 0.223 ) < 0.001, 1, "score - overall 2");

# increment again and check score - 4 tests
$off_target_2->exonerate_exon_alignments( 'Zv9_NA1:403-425:-1' );
is( $off_target_2->number_exonerate_exon_hits, 2, "num exo exon hits - 2");
is( join(',', @{$off_target_2->exonerate_exon_alignments}), '17:403-425:-1,Zv9_NA1:403-425:-1', 'exo alignments 2');

is( abs($off_target_2->exonerate_score - 0.422 ) < 0.001, 1, "score - exo 2");
#print 'Seed score:', $off_target_2->seed_score, "\n";
#print 'Exo score:', $off_target_2->exonerate_score, "\n";
#print 'overall score:', $off_target_2->score, "\n";
is( abs($off_target_2->score - 0.178 ) < 0.001, 1, "score - overall 2");


open my $fh, '<', $test_data or die "Couldn't open file: $test_data!\n";
while(<$fh>){
    chomp;
    my @test_data = split /\s/, $_;
    my $id = $test_data[14];
    
    my @seed_hits = split /\//, $test_data[25];
    my @exonerate_hits = split /\//, $test_data[27];
    
    my $off_target = Crispr::OffTarget->new(
        crRNA_name => $test_data[14],
        number_seed_intron_hits => $seed_hits[1],
        number_seed_nongenic_hits => $seed_hits[2],
        number_exonerate_intron_hits => $exonerate_hits[1],
        number_exonerate_nongenic_hits => $exonerate_hits[2],
        seed_exon_alignments => [  ],
        exonerate_exon_alignments => [  ],
        off_target_method => 'exonerate',
    );
    my $seed_exon_hits;
    if( $seed_hits[0] ne '0' ){
        my @seed_alignments = split /,/, $seed_hits[0];
        $off_target->seed_exon_alignments( \@seed_alignments );
        $seed_exon_hits = scalar @seed_alignments;
    }
    else{
        $seed_exon_hits = 0;
    }
    
    my $exonerate_exon_hits;
    if( $exonerate_hits[0] ne '0' ){
        my @alignments = split /,/, $exonerate_hits[0];
        $off_target->exonerate_exon_alignments( \@alignments );
        $exonerate_exon_hits = scalar @alignments;
    }
    else{
        $exonerate_exon_hits = 0;
    }
    
    # test attributes - 9 tests
    is( $off_target->crRNA_name, $id, "name - $id");
    is( $off_target->number_seed_exon_hits, $seed_exon_hits, "num seed exon hits - $id");
    is( $off_target->number_seed_intron_hits, $seed_hits[1], "num seed intron hits - $id");
    is( $off_target->number_seed_nongenic_hits, $seed_hits[2], "num seed nongenic hits - $id");
    #print join("\t", $off_target->seed_score, $test_data[24], abs($off_target->seed_score - $test_data[24]), ), "\n";
    is( abs($off_target->seed_score - $test_data[24]) < 0.001, 1, "seed score - $id");

    is( $off_target->number_exonerate_exon_hits, $exonerate_exon_hits, "num exonerate exon hits - $id");
    is( $off_target->number_exonerate_intron_hits, $exonerate_hits[1], "num exonerate intron hits - $id");
    is( $off_target->number_exonerate_nongenic_hits, $exonerate_hits[2], "num exonerate exonerate hits - $id");
    #print join("\t", $off_target->exonerate_score, $test_data[26], abs($off_target->exonerate_score - $test_data[26]), ), "\n";
    is( abs($off_target->exonerate_score - $test_data[26]) < 0.001, 1, "exonerate score - $id");
}





#my $off_target = Crispr::OffTarget->new(
#    crRNA_name => 'crRNA:1:10000-10022:1',
#    number_seed_intron_hits => 4,
#    number_seed_nongenic_hits => 8,
#    seed_exon_alignments => [ qw( 10:200-222:1 18:505-507:-1 ) ],
#    number_exonerate_intron_hits => 4,
#    number_exonerate_nongenic_hits => 8,
#    exonerate_exon_alignments => [ qw( 5:200-222:1 9:505-507:-1 ) ],
#);
#
## test attributes - 15 tests
#is( $off_target->crRNA_name, 'crRNA:1:10000-10022:1', "name 1" );
#throws_ok{ $off_target->crRNA_name('crRNA:1:10020-10042:1') } qr/read-only/, 'Read-only name throws ok';
#is( abs($off_target->seed_score - 0.279 ) < 0.001, 1, "score - seed");
#is( $off_target->number_seed_exon_hits, 2, "num seed exon hits - 1");
#is( $off_target->number_seed_intron_hits, 4, "num seed intron hits - 1");
#is( $off_target->number_seed_nongenic_hits, 8, "num seed nongenic hits - 1");
#is( ref $off_target->seed_exon_alignments, ARRAY, "class of seed alignments - 1");
#is( join(',', @{ $off_target->seed_exon_alignments }), '10:200-222:1,18:505-507:-1', "seed exon alignments - 1");
#
#is( abs($off_target->exonerate_score - 0.279 ) < 0.001, 1, "exonerate score");
#is( $off_target->number_exonerate_exon_hits, 2, "num exo exon hits - 1");
#is( $off_target->number_exonerate_intron_hits, 4, "num exo intron hits - 1");
#is( $off_target->number_exonerate_nongenic_hits, 8, "num exo nongenic hits - 1");
#is( ref $off_target->exonerate_exon_alignments, ARRAY, "class of mismatch alignments - 1");
#is( join(',', @{ $off_target->exonerate_exon_alignments }), '5:200-222:1,9:505-507:-1', "mismatch alignments - 1");
#
#is( abs($off_target->score - 0.078 ) < 0.001, 1, "score - overall 1");
#
#my $off_target_2 = Crispr::OffTarget->new(
#    crRNA_name => 'crRNA:1:10000-10022:1',
#);
#
## incrementing hits - 13
#is( $off_target_2->number_seed_exon_hits, 0, "initial num seed exon hits - 2");
#$off_target_2->seed_exon_alignments( '17:403-425:-1,10:103-425:1' );
#is( $off_target_2->number_seed_exon_hits, 2, "num seed exon hits - 2");
#is( join(',', @{$off_target_2->seed_exon_alignments}), '17:403-425:-1,10:103-425:1', 'seed alignments 2');
#$off_target_2->increment_seed_intron_hits;
#$off_target_2->increment_seed_intron_hits;
#is( $off_target_2->number_seed_intron_hits, 2, "num seed intron hits - 2");
#$off_target_2->increment_seed_nongenic_hits;
#$off_target_2->increment_seed_nongenic_hits;
#$off_target_2->increment_seed_nongenic_hits;
#$off_target_2->increment_seed_nongenic_hits;
#is( $off_target_2->number_seed_nongenic_hits, 4, "num seed nongenic hits - 2");
##print join("\t", $off_target_2->number_seed_exon_hits, $off_target_2->number_seed_intron_hits, $off_target_2->number_seed_nongenic_hits, $off_target_2->seed_score, ), "\n";
#is( abs($off_target_2->seed_score - 0.422 ) < 0.001, 1, "score - seed 2");
#
#is( $off_target_2->number_exonerate_exon_hits, 0, "initial num exo exon hits - 2");
#$off_target_2->exonerate_exon_alignments( '17:403-425:-1' );
#is( $off_target_2->number_exonerate_exon_hits, 1, "num exo exon hits - 2");
#is( join(',', @{$off_target_2->exonerate_exon_alignments}), '17:403-425:-1', 'exo alignments 2');
#$off_target_2->increment_exonerate_intron_hits;
#$off_target_2->increment_exonerate_intron_hits;
#is( $off_target_2->number_exonerate_intron_hits, 2, "num exo intron hits - 2");
#$off_target_2->increment_exonerate_nongenic_hits;
#$off_target_2->increment_exonerate_nongenic_hits;
#$off_target_2->increment_exonerate_nongenic_hits;
#$off_target_2->increment_exonerate_nongenic_hits;
#is( $off_target_2->number_exonerate_nongenic_hits, 4, "num exo nongenic hits - 2");
#is( abs($off_target_2->exonerate_score - 0.528 ) < 0.001, 1, "score - exo 2");
#
#is( abs($off_target_2->score - 0.223 ) < 0.001, 1, "score - overall 2");
#
## increment again and check score - 4 tests
#$off_target_2->exonerate_exon_alignments( 'Zv9_NA1:403-425:-1' );
#is( $off_target_2->number_exonerate_exon_hits, 2, "num exo exon hits - 2");
#is( join(',', @{$off_target_2->exonerate_exon_alignments}), '17:403-425:-1,Zv9_NA1:403-425:-1', 'exo alignments 2');
#
#is( abs($off_target_2->exonerate_score - 0.422 ) < 0.001, 1, "score - exo 2");
##print 'Seed score:', $off_target_2->seed_score, "\n";
##print 'Exo score:', $off_target_2->exonerate_score, "\n";
##print 'overall score:', $off_target_2->score, "\n";
#is( abs($off_target_2->score - 0.178 ) < 0.001, 1, "score - overall 2");
#
#
#open my $fh, '<', $test_data or die "Couldn't open file: $test_data!\n";
#while(<$fh>){
#    chomp;
#    my @test_data = split /\s/, $_;
#    my $id = $test_data[14];
#    
#    my @seed_hits = split /\//, $test_data[25];
#    my @exonerate_hits = split /\//, $test_data[27];
#    
#    my $off_target = Crispr::OffTarget->new(
#        crRNA_name => $test_data[14],
#        number_seed_intron_hits => $seed_hits[1],
#        number_seed_nongenic_hits => $seed_hits[2],
#        number_exonerate_intron_hits => $exonerate_hits[1],
#        number_exonerate_nongenic_hits => $exonerate_hits[2],
#    );
#    my $seed_exon_hits;
#    if( $seed_hits[0] ne '0' ){
#        my @seed_alignments = split /,/, $seed_hits[0];
#        $off_target->seed_exon_alignments( \@seed_alignments );
#        $seed_exon_hits = scalar @seed_alignments;
#    }
#    else{
#        $seed_exon_hits = 0;
#    }
#    
#    my $exonerate_exon_hits;
#    if( $exonerate_hits[0] ne '0' ){
#        my @alignments = split /,/, $exonerate_hits[0];
#        $off_target->exonerate_exon_alignments( \@alignments );
#        $exonerate_exon_hits = scalar @alignments;
#    }
#    else{
#        $exonerate_exon_hits = 0;
#    }
#    
#    # test attributes - 9 tests
#    is( $off_target->crRNA_name, $id, "name - $id");
#    is( $off_target->number_seed_exon_hits, $seed_exon_hits, "num seed exon hits - $id");
#    is( $off_target->number_seed_intron_hits, $seed_hits[1], "num seed intron hits - $id");
#    is( $off_target->number_seed_nongenic_hits, $seed_hits[2], "num seed nongenic hits - $id");
#    #print join("\t", $off_target->seed_score, $test_data[24], abs($off_target->seed_score - $test_data[24]), ), "\n";
#    is( abs($off_target->seed_score - $test_data[24]) < 0.001, 1, "seed score - $id");
#
#    is( $off_target->number_exonerate_exon_hits, $exonerate_exon_hits, "num exonerate exon hits - $id");
#    is( $off_target->number_exonerate_intron_hits, $exonerate_hits[1], "num exonerate intron hits - $id");
#    is( $off_target->number_exonerate_nongenic_hits, $exonerate_hits[2], "num exonerate exonerate hits - $id");
#    #print join("\t", $off_target->exonerate_score, $test_data[26], abs($off_target->exonerate_score - $test_data[26]), ), "\n";
#    is( abs($off_target->exonerate_score - $test_data[26]) < 0.001, 1, "exonerate score - $id");
#}
