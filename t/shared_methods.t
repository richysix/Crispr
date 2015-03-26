#!/usr/bin/env perl
# shared_methods.t - script to test

use warnings;
use strict;
use autodie;

use Test::More;
use Test::Exception;
use Test::Warn;
use Test::MockObject;
use Data::Dumper;
use DateTime;

{
    package Role::Consumer;
    use Moose;
    with 'Crispr::SharedMethods';
    
}

my $tests;

# test methods provided in role
my $role_consumer = Role::Consumer->new();

isa_ok( $role_consumer, 'Role::Consumer' );
$tests++;

# check attributes and methods - 9 tests
my @attributes = (
);

my @methods = ( qw{ _parse_date _build_date } );

foreach my $attribute ( @attributes ) {
    can_ok( $role_consumer, $attribute );
    $tests++;
}
foreach my $method ( @methods ) {
    can_ok( $role_consumer, $method );
    $tests++;
}

# test _parse_date
ok( $role_consumer->_parse_date('1979-02-24'), '_parse_date ok date' );
throws_ok { $role_consumer->_parse_date('1979-02-2') }
    qr/The date supplied is not a valid format/, "_parse_date throws on date that doesn't match yyyy-mm-dd";
$tests+=2;

# test _build_date
is( $role_consumer->_build_date->ymd, DateTime->now()->ymd, '_build date' );
$tests++;

# test _parse_crispr_guide_name
#TODO: {
#    local $TODO = 'method does not exist yet';
#    ok( $role_consumer->_parse_crispr_guide_name( '7_A01' ), '_parse_crispr_guide_name 7_A01' );
#}

done_testing( $tests );

__END__

=pod

=head1 NAME

shared_methods.t

=head1 DESCRIPTION

test file for Crispr::SharedMethods Role

=cut

=head1 SYNOPSIS

    prove -l shared_methods.t

=head1 DEPENDENCIES

Moose
Crispr

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