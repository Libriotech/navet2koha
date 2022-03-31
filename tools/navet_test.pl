#!/usr/bin/perl

=pod

=encoding UTF8

=head1 navet_test.pl

Tiny script to test your config is OK.

=head1 DESCRIPTION

Takes two arguments: the path to the navet2koha config
and a "personnummer" (social security number). Will
look up the person identified by the personnummer, and
output the names of that person, if the lookup succeeds.
If it fails, as much information as possible will be
given about the error.

=head1 USAGE

  $ sudo koha-shell -c "perl navet_test.pl /path/to/navet-config.yaml personnr" bth

=cut

use Modern::Perl;
use Navet::ePersondata::Personpost;
use YAML::Syck;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
binmode STDOUT, ":utf8";
use utf8;

die "Usage: $0 </path/to/navet-config.yaml> <personnr>" unless $ARGV[0] && $ARGV[1];

my $config = LoadFile( $ARGV[0] );
$config->{'verbose'} = 1;

my $ep = Navet::ePersondata::Personpost->new(

    pkcs12_file     => $config->{ 'pkcs12_file' },
    pkcs12_password => $config->{ 'pkcs12_password' },
    OrgNr           => $config->{ 'OrgNr' },
    BestallningsId  => $config->{ 'BestallningsId' },

);

my $node = $ep->find_first({ PersonId => $ARGV[1] });

if ( my $err = $ep->error) {

    say Dumper $err;

} else {

    say Dumper $node;

    say $node->findvalue( './Personpost/Namn/Fornamn' );
    say $node->findvalue( './Personpost/Namn/Mellannamn' );
    say $node->findvalue( './Personpost/Namn/Efternamn' );

}
