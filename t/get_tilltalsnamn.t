#!/usr/bin/perl

use Data::Dumper;
use Modern::Perl;
use Test2::V0;
use Test2::Bundle::More;
plan 11;

use lib 'lib';
use Util;

# get_tilltalsnamn

my $firstname1 = "a b c";

is( Util::get_tilltalsnamn( $firstname1, '10' ), 'a', '10 ok' );
is( Util::get_tilltalsnamn( $firstname1, '20' ), 'b', '20 ok' );
is( Util::get_tilltalsnamn( $firstname1, '30' ), 'c', '30 ok' );

is( Util::get_tilltalsnamn( $firstname1, '12' ), 'a b', '12 ok' );
is( Util::get_tilltalsnamn( $firstname1, '23' ), 'b c', '23 ok' );
is( Util::get_tilltalsnamn( $firstname1, '13' ), 'a c', '13 ok' );

my $firstname2 = "a-b c";

is( Util::get_tilltalsnamn( $firstname2, '10' ), 'a', '10 ok with hyphen' );
is( Util::get_tilltalsnamn( $firstname2, '20' ), 'b', '20 ok with hyphen' );
is( Util::get_tilltalsnamn( $firstname2, '30' ), 'c', '30 ok with hyphen' );

is( Util::get_tilltalsnamn( $firstname2, '12' ), 'a-b', '12 ok with hyphen' );
is( Util::get_tilltalsnamn( $firstname2, '23' ), 'b c', '23 ok with hyphen' );
