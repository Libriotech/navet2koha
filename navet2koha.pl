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
                <Mellannamn>Meddel</Mellannamn>
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

# Uncomment the line below to get debug output from the SOAP dialogue 
# with Navet, including a dump of all data received as XML.
# use SOAP::Lite ( +trace => 'all', readable => 1, outputxml => 1, );

use Navet::ePersondata::Personpost;
use Se::PersonNr;
use Getopt::Long;
use Data::Dumper;
$Data::Dumper::Sortkeys = 1;
use Template;
use DateTime;
use Try::Tiny;
use YAML::Syck;
use Pod::Usage;
use Modern::Perl;
binmode STDOUT, ":utf8";

use Koha::Patrons;
use Koha::Patron::Attributes;

my $dt = DateTime->now;

# Get options
my ( $borrowernumbers, $configfile, $capture_names, $limit, $offset, $test_mode, $verbose, $debug ) = get_options();

# Get the config from file and add verbose and debug to it
if ( !-e $configfile ) { die "The file $configfile does not exist..."; }
my $config = LoadFile( $configfile );
$config->{'verbose'} = $verbose;
$config->{'debug'}   = $debug;

# Set up a file for capturing names
my $names;
if ( $capture_names ) {
    open( $names, '>>', $capture_names ) or die "Could not open file '$capture_names' $!";
}

# Set up logging if requested
my $log;
if ( defined $config->{'logdir'} ) {
    my $filename = 'navet2koha-' . $dt->ymd('-') . 'T' . $dt->hms('') . '.log';
    my $logpath = $config->{'logdir'} . '/' . $filename;
    open( $log, '>>', $logpath ) or die "Could not open file '$logpath' $!";
}

say $log "!!! Running in test mode, not data in Koha will be changed/updated!" if $test_mode && $config->{'logdir'};

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
        say $log "*** Looking at borrowernumber=$borrowernumber ***" if $config->{'logdir'};
        my $patron = Koha::Patrons->find({ borrowernumber => $borrowernumber });
        unless ( $patron ) {
            say $log "Patron not found for borrowernumber=$borrowernumber" if $config->{'logdir'};
            next BORRNUM;
        }
        say $log "Looking..." if $config->{'logdir'};
        _process_borrower( $patron );
        say $log "Done." if $config->{'logdir'};
    }

} else {

    my $count = 0;
    my $patrons = Koha::Patrons->search();
    PATRON: while ( my $patron = $patrons->next ) {
        $count++;
        say $log "*** $count Looking at borrowernumber=" . $patron->borrowernumber . "***" if $config->{'logdir'};
        # Implement --offset
        next PATRON if $offset && $count < $offset;
        _process_borrower( $patron );
        # Implement --limit
        last PATRON if $limit && $count == $limit;
    }

}

say $log "Done at " . $dt->ymd('-') . 'T' . $dt->hms('') if $config->{'logdir'};

sub _process_borrower {

    my ( $borrower ) = @_;

    # Some patrons have a hidden address. These should not be updated with data
    # from Navet. Such patrons should have an extended patron attribute set to 1.
    # The name of the attribute is specified by the "protected_attribute" config
    # variable.
    my $protected = Koha::Patron::Attributes->search({
        'borrowernumber' => $borrower->borrowernumber,
        'code'           => $config->{ 'protected_attribute' },
    });
    if ( $protected && $protected->count > 0 && $protected->next->attribute == 1 ) {
        say $log "Protected patron" if $config->{'logdir'};
        return undef;
    } else {
        say $log "Not protected" if $config->{'logdir'};
    }

    # Check the social security number makes sense
    my $socsec_attr = Koha::Patron::Attributes->search({
        'borrowernumber' => $borrower->borrowernumber,
        'code'           => $config->{ 'socsec_attribute' },
    });
    unless ( $socsec_attr && $socsec_attr->count ) {
        say $log "Personnummer not found" if $config->{'logdir'};
        return undef;
    } else {
        say $log "Personnummer found" if $config->{'logdir'};
    }
    my $socsec = $socsec_attr->next->attribute;
    if ( length $socsec != 12 ) {
        say $log "FAIL $socsec Wrong length" if $config->{'logdir'};
        return undef;
    } else {
        say $log "Correct length" if $config->{'logdir'};
    }
    my $pnr = new Se::PersonNr( $socsec );
    if ( ! $pnr->is_valid() ) {
        say $log "FAIL $socsec Rejected by Se::PersonNr (checksum should be ". $pnr->get_valid() . ")" if $config->{'logdir'};
        return undef;
    } else {
        say $log "Accepted by Se::PersonNr" if $config->{'logdir'};
    }

    # Get the data from Navet
    my $node;
    try {
        say $log "Looking up PersonId => $socsec" if $config->{'logdir'};
        $node = $ep->find_first({ PersonId => $socsec });
        say $log "Done looking up" if $config->{'logdir'};
    } catch {
        warn "caught error: $_"; # not $@
        if ( my $err = $ep->error) {
            say $log "Error:" if $config->{'logdir'};
            say $log 'message: ' .          $err->{message} if $config->{'logdir'};          # error text
            say $log 'soap_faultcode: ' .   $err->{soap_faultcode} if $config->{'logdir'};   # SOAP faultcode from /Envelope/Body/Fault/faultscode
            say $log 'soap_faultstring: ' . $err->{soap_faultstring} if $config->{'logdir'}; # SOAP faultstring from /Envelope/BodyFault/faultstring
            say $log 'sv_Felkod: ' .        $err->{sv_Felkod} if $config->{'logdir'};        # Extra error code provided by Skatteverket
            say $log 'sv_Beskrivning: ' .   $err->{sv_Beskrivning} if $config->{'logdir'};   # Extra description provided by Skatteverket
            say $log 'raw_error: ' .        $err->{raw_error} if $config->{'logdir'};        # Unparsed error text (can be XML, HTML or plain text)
            say $log 'https_status: ' .     $err->{https_status} if $config->{'logdir'};     # HTTP status code
        }
        # TODO Is there some way we can try the patron again later?
    };

    # say $log "Do we have a node?" if $config->{'logdir'};
    return undef unless $node;
    # say $log "We have a node" if $config->{'logdir'};
    # say $log Dumper join ' ', $node->findvalue('./Personpost/Namn/Fornamn') if $config->{'logdir'};

    if ( $capture_names ) {

        say $names '"' . $node->findvalue( './Personpost/Namn/Fornamn' ) . '","' . $node->findvalue( './Personpost/Namn/Mellannamn' ) . '","' . $node->findvalue( './Personpost/Namn/Efternamn' ) . '"';

    } else {
        # Walk through the data and see if Koha and Navet differ
        my $is_changed = 0;
        foreach my $key ( sort keys %{ $config->{ 'patronmap' } } ) {

            print $log $key . ' Koha="' . $borrower->$key . '" <=> Navet="' . $node->findvalue( $config->{ 'patronmap' }->{ $key } ) . '"' if $config->{'logdir'};
            if ( $borrower->$key eq $node->findvalue( $config->{ 'patronmap' }->{ $key } ) ) {
                print $log ' -> equal' if $config->{'logdir'};
            } else {
                print $log ' -> NOT equal' if $config->{'logdir'};
                $is_changed = 1;
                # Update the object
                $borrower->$key( $node->findvalue( $config->{ 'patronmap' }->{ $key } ) );
            }
            print $log "\n" if $config->{'logdir'};
        
        }

        # Only save if we have some changes
        if ( $is_changed == 1 ) {
            say $log "Going to update borrower" if $config->{'logdir'};
            if ( $test_mode == 0 ) {
                $borrower->store;
            } else {
                say $log "Running in test mode, not updating" if $config->{'logdir'};
            }
            say $log "Done" if $config->{'logdir'};
        }

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

=item B<--capture_names>

Path to file where names from Navet should be captured.

Navet provides separate fields for firstname, middlename and surname. It might
necessary to inspect how names are split across these fields. If B<--capture_names>
is enabled, no updates will be made, but names will be written to a comma separated
file in the current working directory, with the name B<captured_names.txt>.

=item B<-l, --limit>

Only process the n first patrons. Does not work with --borrowernumbers.

=item B<-o, --offset>

Skip the n first patrons. Does not work with --borrowernumbers.

=item B<-t, --test>

Run in test mode. No data will be changed/saved in Koha.

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
    my $borrowers     = '';
    my $configfile    = '';
    my $capture_names = '';
    my $limit         = '';
    my $offset        = '';
    my $test_mode     = 0;
    my $verbose       = '';
    my $debug         = '';
    my $help          = '';

    GetOptions (
        'b|borrowernumbers=s' => \$borrowers,
        'c|configfile=s'      => \$configfile,
        'capture_names=s'     => \$capture_names,
        'l|limit=i'           => \$limit,
        'o|offset=i'          => \$offset,
        't|test'              => \$test_mode,
        'v|verbose'           => \$verbose,
        'd|debug'             => \$debug,
        'h|?|help'            => \$help
    );

    pod2usage( -exitval => 0 ) if $help;
    pod2usage( -msg => "\nMissing Argument: -c, --configfile required\n", -exitval => 1 ) if !$configfile;

    return ( $borrowers, $configfile, $capture_names, $limit, $offset, $test_mode, $verbose, $debug );

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
