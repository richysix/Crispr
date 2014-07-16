#!/usr/bin/env perl
# config.t
use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use Getopt::Long;

my $tests = 0;

use Crispr::Config;

# create tmp config file
open my $tmp_fh, '>', 'config.tmp' or die "Couldn't open config.tmp to write to!\n";
print {$tmp_fh} "#key\tvalue\n";
for my $i ( 1..3 ){
    print {$tmp_fh} join("\t", 'key' . $i, 'value' . $i ), "\n";
}
print {$tmp_fh} join("\s", 'key4', 'value4' ), "\n";
close( $tmp_fh );

my $config_obj;
warning_like { $config_obj = Crispr::Config->new( 'config.tmp' ); }
    qr/Line:.*,\sis\snot\sin\scorrect\sformat.\s
    It\sshoud\sbe\sKEY\sVALUE\sseparated\sby\stabs/xms,
    "check warning for line that doesn't fit format";
$tests++;

# check crRNA and attributes
# 1 test
isa_ok( $config_obj, 'Crispr::Config' );
$tests++;

# check method calls 27 tests
my @methods = qw( load_cfg );

foreach my $method ( @methods ) {
    can_ok( $config_obj, $method );
    $tests++;
}

for my $i ( 1..3 ){
    my $k = 'key' . $i;
    my $v = 'value' . $i;
    is( $config_obj->{$k}, $v, 'check keys and values 1');
    $tests++;
}

# remove tmp config file
unlink( 'config.tmp' );

# check warnings and dying
throws_ok{ Crispr::Config->new( 'config.tmp' ) } qr/No\scfg\sfile\sfound\sat/, 'check throws ok on non-existant file';
throws_ok{ Crispr::Config->new() } qr/A\sconfig\sfile\sname\smust\sbe\ssupplied\sto\smethod\snew/, 'check throws ok when no file name supplied';
$tests += 2;

done_testing( $tests );