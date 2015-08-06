package Local::OpenSSL::Script::Revoke;


use strict;
use warnings;
use Template;


our $VERSION = '0.001'; $VERSION = eval "$VERSION";


=pod

=encoding utf-8

=head1 NAME

Local::OpenSSL::Script::Revoke - generate a script file to generate 
a certificate revocation file using the openssl utility.

=cut


my $SH_TEMPLATE =<<'EOF';
#!/bin/sh

DATABASE="[% TARGET_DIRECTORY %]/[% DATABASE_FILE %]"
CRLNUMBER="[% TARGET_DIRECTORY %]/[% CRLNUMBER_FILE %]"

[ ! -f "${DATABASE}" ] || rm ${DATABASE} || exit 1
touch ${DATABASE} || exit 1
echo 01 > ${CRLNUMBER}

[% FOREACH clientCRT = CRTS -%]
openssl ca -revoke [% clientCRT %] -keyfile [% CA_KEY %] -cert [% CA_CRT %] \
  || exit 1
[% END %]
openssl ca -gencrl -keyfile [% CA_KEY %] -cert [% CA_CRT %] -out [% CRL_FILE %] \
  || exit 1

exit 0
EOF


=head1 METHODS

=over 4

=item B<new>( %args )

Creates a Local::OpenSSL::Script::Revoke object. Accepts next
arguments:

=over

=item * TARGET_DIRECTORY

=item * DATABASE_FILE

=item * CRLNUMBER_FILE

=item * CRTS

=item * CA_KEY

=item * CA_CRT

=item * CRL_FILE

=back

=cut


sub new {
  my ( $class, %arg ) = @_;


  my %args =
    (
      'TARGET_DIRECTORY' => './',
      'DATABASE_FILE' => 'index.txt',
      'CRLNUMBER_FILE' => 'crlnumber',
      'CRTS' => [ ],
      'CA_KEY' => 'ca.key',
      'CA_CRT' => 'ca.crt',
      'CRL_FILE' => 'crl.pem',
      map { +uc( $_ ) => $arg{ $_ } } keys %arg
    )
  ;

  $args{ '__error' } = '';
  $args{ '__stash' } = [ ];

  return bless \%args, $class;
}


=item $filepath = B<generate>()

Generates a shell script file. Returns a filepath with a script
on success.

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

  $tt->process( \$SH_TEMPLATE, { %{ $self } } )
    or return $self->_set_error( $tt->error() );

  # flush
  close( $tmp );

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


scalar "Johnyboy - Американская мечта";
