package Local::Templates::OpenSSL::Revoke; {
  use Object::InsideOut qw( Local::Templates::OpenSSL );


  my $TEMPLATE =<<'EOF';
#!/bin/sh

DATABASE="[% TARGET_DIRECTORY %]/[% DATABASE_FILE %]"
CRLNUMBER="[% TARGET_DIRECTORY %]/[% CRLNUMBER_FILE %]"

[ ! -f "${DATABASE}" ] || rm ${DATABASE} || exit 1
touch ${DATABASE} || exit 1
echo 01 > ${CRLNUMBER}

[% FOREACH clientCRT = CRTS -%]
[% OPENSSL %] ca -revoke [% clientCRT %] -keyfile [% CA_KEY %] -cert [% CA_CRT %] \
  || exit 1
[% END %]
[% OPENSSL %] ca -gencrl -keyfile [% CA_KEY %] -cert [% CA_CRT %] -out [% CRL_FILE %] \
  || exit 1

exit 0
EOF


  my @arg_target_directory
    :Field
    :Type(scalar)
    :Arg( 'Name' => 'TARGET_DIRECTORY', 'Default' => '.')
    :Acc(arg_target_directory);
  my @arg_database_file
    :Field
    :Type(scalar)
    :Arg( 'Name' => 'DATABASE_FILE', 'Default' => 'index.txt' )
    :Acc(arg_database_file);
  my @arg_crlnumber_file
    :Field
    :Type(scalar)
    :Arg( 'Name' => 'CRLNUMBER_FILE', 'Default' => 'crlnumber' )
    :Acc(arg_crlnumber_file);
  my @arg_crts
    :Field
    :Arg( CRTS )
    :Type(ARRAY_ref(scalar))
    :Acc(arg_crts);
  my @arg_ca_key
    :Field :Type(scalar)
    :Arg( 'Name' => 'CA_KEY', 'Default' => 'ca.key' )
    :Acc(arg_ca_key);
  my @arg_ca_crt
    :Field
    :Type(scalar)
    :Arg( 'Name' => 'CA_CRT', 'Default' => 'ca.crt' )
    :Acc(arg_ca_crt);
  my @arg_crl_file
    :Field
    :Type(scalar)
    :Arg( 'Name' => 'CRL_FILE', 'Default' => 'crl.pem' )
    :Acc(arg_crl_file);


  sub init :Init {
    my ( $self, $args ) = @_;


    $self->template( $TEMPLATE );
  }


  sub template_args :Cumulative {
    my ( $self ) = @_;


    return 
      (
        'TARGET_DIRECTORY', $self->arg_target_directory(),
        'DATABASE_FILE',    $self->arg_database_file(),
        'CRLNUMBER_FILE',   $self->arg_crlnumber_file(),
        'CRTS',             $self->arg_crts(),
        'CA_KEY',           $self->arg_ca_key(),
        'CA_CRT',           $self->arg_ca_crt(),
        'CRL_FILE',         $self->arg_crl_file(),
      )
    ;
  }

}

1;
