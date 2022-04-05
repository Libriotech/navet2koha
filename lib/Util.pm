=pod

=encoding UTF-8

=head1 Util.pm

Utility functions for navet2koha.

=cut

package Util;

use Modern::Perl;
use Data::Dumper;

=head1 get_tilltalsnamn

  my $tilltalsnamn = get_tilltalsnamn( $firstname, $tilltalsnamnsmarkering );

=cut

sub get_tilltalsnamn {

    my ( $first, $code ) = @_;

    # Remove trailing zero, it does not tell us anything
    $code =~ s/0$//;

    # Split firstname on space or dash, but keep the space or dash
    # https://stackoverflow.com/questions/14907772/split-but-keep-delimiter
    my @names = split /(?<=[ -])/, $first;

    # Assemble the tilltalsnamn
    my $tilltal;
    # Split the code into parts
    my @parts = split //, $code;
    foreach my $part ( @parts ) {
        # Add each part identified in the code to the tilltalsnamn
        $tilltal .= $names[ $part - 1 ];
    }

    # Make sure we return early if we do not have a tilltalsnamn
    return $first unless $tilltal;

    # Remove any trailing space or dash (if "A-B" only wants to keep A)
    $tilltal =~ s/[ -]$//g;

    return $tilltal;

}

1;
