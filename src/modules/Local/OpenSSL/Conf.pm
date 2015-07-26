package Local::OpenSSL::Conf;


use strict;
use warnings;
use Template;
use File::Temp;


our $VERSION = '0.001'; $VERSION = eval "$VERSION";


=pod

=encoding utf-8

=head1 NAME

Local::OpenSSL::Conf - generate custom configuration file
for the openssl utility.

=cut


#
# http://blog.didierstevens.com/2013/05/08/howto-make-your-own-cert-and-revocation-list-with-openssl/
#
my $TEMPLATE =<<'EOF';
[ ca ]
default_ca = myca

[ crl_ext ]
# issuerAltName=issuer:copy  #this would copy the issuer name to altname
authorityKeyIdentifier=keyid:always

[ myca ]
dir = [% TARGET_DIRECTORY %]
new_certs_dir = $dir/newcerts
#unique_subject = no
certificate = $dir/ca.crt
database = $dir/index.txt
private_key = $dir/ca.key
serial = $dir/serial
default_days = [% DEFAULT_DAYS %]
default_md = sha1
policy = myca_policy
x509_extensions = myca_extensions
crlnumber = $dir/crlnumber
default_crl_days = [% DEFAULT_CRL_DAYS %]

[ myca_policy ]
commonName = supplied
stateOrProvinceName = supplied
countryName = optional
emailAddress = optional
organizationName = supplied
organizationalUnitName = optional

[ myca_extensions ]
basicConstraints = CA:false
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always
keyUsage = digitalSignature,keyEncipherment
extendedKeyUsage = serverAuth
crlDistributionPoints = URI:[% CRL_DISTRIBUTION_POINTS %]
subjectAltName = @alt_names

[alt_names]
[% FOREACH server = DNS_SERVERS -%]
DNS.[% loop.index + 1 %] = [% server %]
[% END %]
[% FOREACH addr = HOSTS -%]
IP.[% loop.index + 1 %] = [% addr %]
[% END %]
EOF


=head1 METHODS

=over 4

=item B<new>( %args )

Creates Local::OpenSSL::Conf object. Currently, accepts
next arguments:

=over

=item * TARGET_DIRECTORY

=item * DEFAULT_DAYS

=item * DEFAULT_CRL_DAYS

=item * DNS_SERVERS

=item * CRL_DISTRIBUTION_POINTS

=item * HOSTS

=back

=cut


sub new {
  my ( $class, %arg ) = @_;


  my %args =
    (
      'TARGET_DIRECTORY' => './',
      'DEFAULT_DAYS' => 3650,
      'DEFAULT_CRL_DAYS' => 3650,
      'DNS_SERVERS' => [ ],
      'CRL_DISTRIBUTION_POINTS' => 'http://example.com/root.crl',
      'HOSTS' => [ ],
      map { +uc( $_ ) => $arg{ $_ } } keys %arg
    )
  ;

  $args{ '__error' } = '';
  $args{ '__stash' } = [ ];

  return bless \%args, $class;
}


=item $filepath = B<generate>()

Returns a filepath to a new created configuration file for B<openssl ca>
utility.

Returns nothing if an error has occured. Use a method B<error>() to
retrieve an error message.

=cut


sub generate {
  my ( $self ) = @_;


  $self->_clear_error();

  # TODO
  # File::Temp->new can croak() when failed
  $self->_stash( my $tmp = File::Temp->new() );

  my $tt = Template->new( {
    ENCODING => 'utf8',
    OUTPUT => $tmp,
  } ) or return $self->_set_error( Template->error() );

  $tt->process( \$TEMPLATE, { %{ $self } } )
    or return $self->_set_error( $tt->error() );

  # flush
  close($tmp);


  return $tmp->filename();
}


=item $error_message = B<error>()

Returns last error message.

=cut


sub error {
  $_[0]->{ '__error' };
}

sub _set_error {
  $_[0]->{ '__error' } = $_[1];
  return;
}

sub _clear_error {
  $_[0]->{ '__error' } = '';
}


sub _stash {
  push @{ $_[0]->{ '__stash' } }, $_[1];
}


sub DESTROY {
  %{ $_[0] } = ();
}


=back

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

2015, gh0stwizard

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system itself.

=cut


scalar "Не Ваше Дело records - Юлiя";
