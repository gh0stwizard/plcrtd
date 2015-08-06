package Local::Templates::OpenSSL; {
  use Object::InsideOut qw( Local::Templates );


  my @openssl
    :Field
    :Arg( 'Name' => 'OPENSSL', 'Default' => 'openssl' )
    :Acc( arg_openssl );


  sub template_args :Cumulative {
    my ( $self ) = @_;


    return ( 'OPENSSL', $self->arg_openssl() );
  }

}

1;
