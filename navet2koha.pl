#!/usr/bin/perl 

# Copyright 2019 Magnus Enger Libriotech

=head1 NAME

navet2koha.pl - Syncronize patron data from Navet to Koha.

=head1 SYNOPSIS

 sudo PERL5LIB=/usr/share/koha/lib/ KOHA_CONF=/etc/koha/sites/mykoha/koha-conf.xml perl my_script.pl --configfile /path/to/config.yaml -v

=head1 NON-STANDARD DEPENDENCIES

  sudo cpanm Se::PersonNr

=head1 SAMPLE DATA

This is an example of data returned from the API:

  <?xml version='1.0' encoding='UTF-8'?>
  <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/">
    <S:Body>
      <ns0:PersonpostXMLResponse 
        xmlns:ns1="http://www.skatteverket.se/folkbokforing/na/personpostXML/v2" 
        xmlns:ns0="http://xmls.skatteverket.se/se/skatteverket/folkbokforing/na/epersondata/V1">
        <ns0:Folkbokforingsposter>
          <Folkbokforingspost>
            <Arendeuppgift andringstidpunkt="20200406121712"/>
            <Personpost>
              <PersonId>
                <PersonNr>************</PersonNr>
              </PersonId>
              <Namn>
                <Tilltalsnamnsmarkering>10</Tilltalsnamnsmarkering>
                <Fornamn>Medel</Fornamn>
                <Efternamn>Svensson</Efternamn>
              </Namn>
              <Adresser>
                <Folkbokforingsadress>
                  <Utdelningsadress2>KUNGSGATAN 1</Utdelningsadress2>
                  <PostNr>64136</PostNr>
                  <Postort>KATRINEHOLM</Postort>
                </Folkbokforingsadress>
                <UUID>
                  <Fastighet>...</Fastighet>
                  <Adress>...</Adress>
                  <Lagenhet>...</Lagenhet>
                </UUID>
              </Adresser>
            </Personpost>
          </Folkbokforingspost>
        </ns0:Folkbokforingsposter>
      </ns0:PersonpostXMLResponse>
    </S:Body>
  </S:Envelope>

=cut

# use SOAP::Lite ( +trace => 'all', readable => 1, outputxml => 1, );
use Navet::ePersondata::Personpost;
use Se::PersonNr;
use Getopt::Long;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Template;
use DateTime;
use YAML::Syck;
use Pod::Usage;
use Modern::Perl;
binmode STDOUT, ":utf8";

use C4::Members::Attributes;
use Koha::Patrons;

my $dt = DateTime->now;
my $date = $dt->ymd;

# Get options
my ( $borrowernumbers, $configfile, $limit, $offset, $verbose, $debug ) = get_options();

# Get the config from file and add verbose and debug to it
if ( !-e $configfile ) { die "The file $configfile does not exist..."; }
my $config = LoadFile( $configfile );
$config->{'verbose'} = $verbose;
$config->{'debug'}   = $debug;

my $ep = Navet::ePersondata::Personpost->new(
    # Set proxy to test service instead of production 
#    soap_options => {
#        proxy => 'https://www2.test.skatteverket.se/na/na_epersondata/V2/personpostXML'
#    },
    pkcs12_file     => $config->{ 'pkcs12_file' },
    pkcs12_password => $config->{ 'pkcs12_password' },
    OrgNr           => $config->{ 'OrgNr' },
    BestallningsId  => $config->{ 'BestallningsId' },
);

# Turn a list of borrowernumbers into a list of borrowers
if ( $borrowernumbers ) {

    my @borrnums = split /,/, $borrowernumbers;
    BORRNUM: foreach my $borrowernumber ( @borrnums ) {
        say "*** Looking at borrowernumber=$borrowernumber ***" if $config->{'verbose'};
        my $patron = Koha::Patrons->find({ borrowernumber => $borrowernumber });
        unless ( $patron ) {
            say "Patron not found for borrowernumber=$borrowernumber" if $config->{'verbose'};
            next BORRNUM;
        }
        _process_borrower( $patron );
    }

} else {

    my $count = 0;
    my $patrons = Koha::Patrons->search();
    PATRON: while ( my $patron = $patrons->next ) {
        say "*** Looking at borrowernumber=" . $patron->borrowernumber . "***" if $config->{'verbose'};
        $count++;
        # Implement --offset
        next PATRON if $offset && $count < $offset;
        _process_borrower( $patron );
        # Implement --limit
        last PATRON if $limit && $count == $limit;
    }

}

sub _process_borrower {

    my ( $borrower ) = @_;

    # Some patrons have a hidden address. These should not be updated with data
    # from Navet. Such patrons should have an extended patron attribute set to 1.
    # The name of the attribute is specified by the "protected_attribute" config
    # variable.
    my $protected = C4::Members::Attributes::GetBorrowerAttributeValue( $borrower->borrowernumber, $config->{ 'protected_attribute' } );
    if ( $protected && $protected == 1 ) {
        say "Protected patron";
        return undef;
    }

    # Check the social security number makes sense
    my $socsec    = C4::Members::Attributes::GetBorrowerAttributeValue( $borrower->borrowernumber, $config->{ 'socsec_attribute' } );
    unless ( $socsec ) {
        say "Personnummer not found";
        return undef;
    }
    if ( length $socsec != 12 ) {
        say "FAIL Wrong length: $socsec";
        return undef;
    }
    my $pnr = new Se::PersonNr( $socsec );
    if ( ! $pnr->is_valid() ) {
        say "FAIL Rejected by Se::PersonNr (checksum should be ". $pnr->get_valid() . ")";
        return undef;
    }

    # Get the data from Navet
    my $node = $ep->find_first({ PersonId => $socsec });

    if ( my $err = $ep->error) {
        say "Error:";
        say 'message: ' .          $err->{message};          # error text
        say 'soap_faultcode: ' .   $err->{soap_faultcode};   # SOAP faultcode from /Envelope/Body/Fault/faultscode
        say 'soap_faultstring: ' . $err->{soap_faultstring}; # SOAP faultstring from /Envelope/BodyFault/faultstring
        say 'sv_Felkod: ' .        $err->{sv_Felkod};        # Extra error code provided by Skatteverket
        say 'sv_Beskrivning: ' .   $err->{sv_Beskrivning};   # Extra description provided by Skatteverket
        say 'raw_error: ' .        $err->{raw_error};        # Unparsed error text (can be XML, HTML or plain text)
        say 'https_status: ' .     $err->{https_status};     # HTTP status code
        die;
    }

    # Walk through the data and see if Koha and Navet differ
    my $is_changed = 0;
    foreach my $key ( sort keys %{ $config->{ 'patronmap' } } ) {

        print $key . ' Koha="' . $borrower->$key . '" <=> Navet="' . $node->findvalue( $config->{ 'patronmap' }->{ $key } ) . '"';
        if ( $borrower->$key eq $node->findvalue( $config->{ 'patronmap' }->{ $key } ) ) {
            print ' -> equal';
        } else {
            print ' -> NOT equal';
            $is_changed = 1;
            # Update the object
            $borrower->$key( $node->findvalue( $config->{ 'patronmap' }->{ $key } ) );
        }
        print "\n";
    
    }

    # Only save if we have some changes
    if ( $is_changed == 1 ) {
        say "Going to update borrower";
        $borrower->store;
        say "Done";
    }

}

=head1 OPTIONS

=over 4

=item B<-b, --borrowernumbers>

One or more borrowernumbers to look up. If more than one borrowernumber is given,
they should be separated by commas, without any spaces. Example:

  --borrowernumbers 123456789,234567890

=item B<-c, --configfile>

Path to config file in YAML format.

=item B<-l, --limit>

Only process the n first patrons. Does not work with --borrowernumbers.

=item B<-o, --offset>

Skip the n first patrons. Does not work with --borrowernumbers.

=item B<-v --verbose>

More verbose output.

=item B<-d --debug>

Even more verbose output.

=item B<-h, -?, --help>

Prints this help message and exits.

=back

=cut

sub get_options {

    # Options
    my $borrowers  = '';
    my $configfile = '';
    my $limit      = '';
    my $offset     = '';
    my $verbose    = '';
    my $debug      = '';
    my $help       = '';

    GetOptions (
        'b|borrowernumbers=s' => \$borrowers,
        'c|configfile=s'      => \$configfile,
        'l|limit=i'           => \$limit,
        'o|offset=i'          => \$offset,
        'v|verbose'           => \$verbose,
        'd|debug'             => \$debug,
        'h|?|help'            => \$help
    );

    pod2usage( -exitval => 0 ) if $help;
    pod2usage( -msg => "\nMissing Argument: -c, --configfile required\n", -exitval => 1 ) if !$configfile;

    return ( $borrowers, $configfile, $limit, $offset, $verbose, $debug );

}

=head1 AUTHOR

Magnus Enger, <magnus [at] libriotech.no>

=head1 LICENSE

 This program is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 You should have received a copy of the GNU General Public License
 along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut
