#!/usr/bin/perl

=pod

=encoding UTF-8

=head1 test_tilltalsnamn

Takes the file produced by running navet2koha with --capture_names and outputs
all the conversions from regular name to tilltalsname.

=cut

use Modern::Perl;
use Text::CSV qw( csv );
use Data::Dumper;
binmode STDOUT, ":utf8";

use FindBin qw($Bin);
use lib "$Bin/../lib";
use Util;

die "Usage: $0 names.csv" unless $ARGV[0];

my $data = csv (
    in         => $ARGV[0],
    detect_bom => 1,
    binary     => 1,
    sep        => ',',
    quote_char => '"',
    allow_loose_quotes => 1,
    # encoding   => "UTF-8",
)  or die Text::CSV->error_diag;

PERSON: foreach my $p ( @{ $data } ) {

    next PERSON if $p->{ 'tilltal' } eq '';
    
    my $firstname   = $p->{ 'firstname' };
    my $middlename  = $p->{ 'middlename' };
    my $surname     = $p->{ 'surname' };
    my $tilltalcode = $p->{ 'tilltal' };

    my $tilltalname = Util::get_tilltalsnamn( $firstname, $tilltalcode );

    say "$tilltalcode $firstname $middlename $surname ==> $tilltalname $middlename $surname";

}


