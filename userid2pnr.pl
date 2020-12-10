#!/usr/bin/perl

# Usage: sudo koha-shell -c "perl userid2pnr.pl" mykoha

use Modern::Perl;
use Data::Dumper;
use C4::Members::Attributes qw( GetBorrowerAttributes UpdateBorrowerAttribute SetBorrowerAttributes );
use Koha::Patrons;

my $patrons = Koha::Patrons->search();

my $count = 0;
while ( my $p = $patrons->next ) {

    my $uid = $p->userid;

    # Only proceed if we have a 10 digit string
    next unless $uid =~ m/^[0-9]{10}$/;

    # Grab the two first digits
    my $year = substr $uid, 0, 2; 

    my $prefix = '19';
    if ( $year < 15 ) {
        $prefix = '20';
    }

    my $pnr = "$prefix$uid";
    say "$uid $pnr";

    # my $value = C4::Members::Attributes::GetBorrowerAttributeValue($p->borrowernumber, 'PERSNUMMER');
    # $value = '' unless $value;

    my $attrs = GetBorrowerAttributes( $p->borrowernumber );
    say Dumper $attrs;
    my @updated_attrs;
    foreach my $attr ( @{ $attrs } ) {
        # Update existing attribute
        if ( $attr->{ 'code' } eq 'PERSNUMMER' ) {
            say "Setting value=$pnr";
            $attr->{ 'value' } = $pnr;
            # UpdateBorrowerAttribute( $p->borrowernumber, $attr );
        }
        say Dumper $attr;
        push @updated_attrs, $attr;
    }
    say Dumper @updated_attrs;
    SetBorrowerAttributes( $p->borrowernumber, \@updated_attrs );

    $count++;
    if ( $count == 2 ) {
        exit;
    }

}
