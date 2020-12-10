#!/usr/bin/perl

# Usage: sudo koha-shell -c "perl userid2pnr.pl" mykoha

use Modern::Perl;
use Data::Dumper;
use C4::Members::Attributes qw( GetBorrowerAttributes UpdateBorrowerAttribute SetBorrowerAttributes );
use Koha::Patrons;

my $patrons = Koha::Patrons->search();

my $count = 0;
PATRON: while ( my $p = $patrons->next ) {

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
    my $personnummer_found = 0;
    ATTR: foreach my $attr ( @{ $attrs } ) {
        # Update existing attribute
        if ( $attr->{ 'code' } eq 'SKYDDAD' && $attr->{ 'value' } eq '1' ) {
            say "SKYDDAD";
            next PATRON;
        }
        if ( $attr->{ 'code' } eq 'PERSNUMMER' ) {
            if ( $attr->{ 'value' } == $pnr ) {
                say "Old value equals new value";
                next PATRON;
            }
            say "Setting value=$pnr";
            $attr->{ 'value' } = $pnr;
            $personnummer_found = 1;
            # UpdateBorrowerAttribute( $p->borrowernumber, $attr );
        }
        say Dumper $attr;
        push @updated_attrs, $attr;
    }
    if ( $personnummer_found == 0 ) {
        # Add a new attribute
        my $a  = {
            'value'             => $pnr,
            'description'       => 'Personnummer',
            'class'             => '',
            'code'              => 'PERSNUMMER',
            'value_description' => undef,
            'category_code'     => undef,
            'display_checkout'  => 0,
        };
        push @updated_attrs, $a;
    }
    say Dumper \@updated_attrs;
    SetBorrowerAttributes( $p->borrowernumber, \@updated_attrs );

    $count++;
    if ( $count == 100 ) {
        # exit;
    }

}
