#!/usr/bin/perl

# (c) 2015-2016, Vitaliy V. Tokarev aka gh0stwizard
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as the Perl 5 programming language system itself.


=pod

=encoding utf-8

=head1 NAME

The application for the Feersum: B<plcrtd> project.

=cut


use strict;
use common::sense;
use AnyEvent;
use AnyEvent::Util;
use HTTP::Body ();
use JSON::XS qw( encode_json decode_json );
use Scalar::Util ();
use HTML::Entities ();
use Encode qw( decode_utf8 );
use File::Spec::Functions qw( catdir catfile );
use Cwd qw( realpath );
use Local::DB::UnQLite;
use Local::OpenSSL::Conf;
use Local::OpenSSL::Script::Revoke;


# body checks
sub MIN_BODY_SIZE() { 4 };
sub MAX_BODY_SIZE() { 524288 };

# read buffer size
sub RDBUFFSIZE()    { 32 * 1024 };

# http headers for responses
my @HEADER_JSON = ( 'Content-Type' => 'application/json; charset=UTF-8' );

# ref.: openssl dgst --help
my %DIGESTS =
  (
     'MD5'       => '-md5',
     'SHA1'      => '-sha1',
     'SHA224'    => '-sha224',
     'SHA256'    => '-sha256',
     'SHA384'    => '-sha384',
     'SHA512'    => '-sha512',
     'RIPEMD160' => '-ripemd160',
     'WHIRLPOOL' => '-whirlpool',
  )
;


=head1 FUNCTIONS

=over 4

=cut


sub NO_ERROR()          { 0 };
sub BAD_REQUEST()       { 1 };
sub NOT_IMPLEMENTED()   { 2 };
sub INTERNAL_ERROR()    { 3 };
sub INVALID_NAME()      { 4 }; # Invalid entry name
sub DUPLICATE_ENTRY()   { 5 };
sub ENTRY_NOT_FOUND()   { 6 };
sub MISSING_DATABASE()  { 7 }; # Missing target database name


=item B<app>( $request )

The main application function. Accepts one argument with
request object $request.

=cut


sub app {
  my ( $R ) = @_;


  my $env = $R->env();

  $env->{ 'REQUEST_METHOD' } eq 'POST'
    ? &process_request
      (
        $R,
        @$env{ qw( psgi.input CONTENT_LENGTH CONTENT_TYPE ) },
      )
    : _405( $R )
  ;

  return;
}


=item $params_h = B<get_params>( $request, $length, $content_type )

Reads HTTP request body. Returns hash reference with request parameters.
A key represents a name of parameter and it's value represents an actual value.

=cut


sub get_params($$$) {
  my ( $r, $len, $content_type ) = @_;


  # reject empty, small or very big requests
  ( ( $len < &MIN_BODY_SIZE() ) || ( $len > &MAX_BODY_SIZE() ) )
    and return;

  my $body = HTTP::Body->new( $content_type, $len );
  # cleanup all temp. files, including upload
  $body->cleanup( 1 );

  my $pos = 0;
  my $chunk = ( $len > &RDBUFFSIZE() ) ? &RDBUFFSIZE() : $len;

  while ( $pos < $len ) {
    $r->read( my $buf, $chunk ) or last;
    $body->add( $buf );
    $pos += $chunk;
  }

  $r->close();

  # FIXME
  # either disable an option $body->cleanup( 1 );
  # or read files later, but doing cleanup itself
  my $result = $body->param();
  my $files = $body->upload();
  
  for my $param ( keys %{ $files } ) {
    if ( exists $result->{ $param } ) {
      AE::log alert => "duplicate parameter %s", $param;
      next;
    }

    my $file = $files->{ $param }{ 'tempname' };
#    my $size = $files->{ $param }{ 'size' };

    if ( open( my $fh, "<", $file ) ) {
      $result->{ $param } = do { local $/; <$fh> }; # XXX
      close( $fh );
    } else {
      AE::log error => "open %s: %s", $file, $!;
    }
  }

  return $result;
}


=item $json = B<process_request>( $feersum, $request, $length, $content_type )

Process a request (POST).

=cut


sub process_request($$$$) {
  my $R = shift;
  my $params = &get_params (@_)
    or return &send_error ($R, &BAD_REQUEST());


  my $action = delete $params->{ 'action' } || '';

  AE::log trace => $action;
  AE::log trace => "  %s = %s", $_, $params->{ $_ }
    for sort keys %{ $params };

  for ( $action ) {
    # returns all database entries
    when ( 'ListDBs' ) {
      &list_dbs( $R );
    }

    # creates new database
    when ( 'CreateDB' ) {
      my $db_name = $params->{ 'name' } || '';
      my $db_desc = $params->{ 'desc' } || '';

      &create_db( $R, $db_name, $db_desc );
    }

    # removes a database and related files
    when ( 'RemoveDB' ) {
      my $db_name = $params->{ 'name' } || '';

      &remove_db( $R, $db_name );
    }

    # returns current database
    when ( 'SwitchDB' ) {
      my $db_name = $params->{ 'name' } || '';

      &switch_db( $R, $db_name );
    }

    # updates database settings
    when ( 'UpdateDB' ) {
      my $db_name = $params->{ 'name' } || '';
      my $db_desc = $params->{ 'desc' } || '';

      &update_db( $R, $db_name, $db_desc );
    }

    # removes all user database entries
    when ( 'RemoveAllDBs' ) {
      &remove_all_dbs( $R );
    }

    # returns a name of current user database
    when ( 'CurrentDB' ) {
      &current_db( $R );
    }

    # generates new private key and stores into user database
    when ( 'genkey' ) {
      my $name = $params->{ 'name' } || '';
      my $type = $params->{ 'type' } || 'RSA';
      my $bits = int( $params->{ 'bits' } || 0 );
      my $cipher = $params->{ 'cipher' } || '';
      my $passwd = $params->{ 'passwd' } || '';

      &genkey( $R, $name, $type, $bits, $cipher, $passwd );
    }

    # removes a private key from an user database
    when ( 'RemoveKey' ) {
      my $name = $params->{ 'name' } || '';

      &remove_key( $R, $name );
    }

    # return a list of all private keys
    when ( 'ListKeys' ) {
      &list_keys( $R );
    }

    # removes all entries for private keys from an user database
    when ( 'RemoveAllKeys' ) {
      &remove_all_keys( $R );
    }

    # generates new certificate requests and stores into user database
    when ( 'gencsr' ) {
      my $name = $params->{ 'name' } || '';
      my %options = map { +"$_" => $params->{ $_ } || '' } 
        qw ( keyname subject keypass digest );

      &gencsr( $R, $name, %options );
    }

    # list of certificate requests
    when ( 'ListCSRs' ) {
      &list_csrs( $R );
    }

    # remove a certificate request
    when ( 'RemoveCSR' ) {
      my $csr_name = $params->{ 'name' } || '';

      &remove_csr( $R, $csr_name );
    }

    # removes all certificate requests from an user database
    when ( 'RemoveAllCSRs' ) {
      &remove_all_csrs( $R );
    }

    # generates new certificate and stores into user database
    when ( 'gencrt' ) {
      my $name = $params->{ 'name' } || '';
      my $days = int( $params->{ 'days' } || 30 );
      my $desc = $params->{ 'desc' } || '';
      my $template = $params->{ 'template' } || 'Default';

      my %settings = 
        (
          days      => $days,
          desc      => $desc,
          template  => $template,
        )
      ;

      if ( defined ( my $csrname = $params->{ 'csrname' } ) ) {
        # self-signed certificate
        $settings{ 'csrname' }  = $csrname;

        for ( qw( cacrt cakey cakeypw ) ) {
          $settings{ $_ } = $params->{ $_ } || '';
        }

      } else {
        # common certificate
        for ( qw( keyname keypass subject digest ) ) {
          $settings{ $_ } = $params->{ $_ } || '';
        }
      }

      &gencrt( $R, $name, %settings );
    }

    # return a list of all certificates
    when ( 'ListCRTs' ) {
      &list_crts( $R );
    }

    # remove a certificate
    when ( 'RemoveCRT' ) {
      my $crt_name = $params->{ 'name' } || '';

      &remove_crt( $R, $crt_name );
    }

    # removes all certificates from an user database
    when ( 'RemoveAllCRTs' ) {
      &remove_all_crts( $R );
    }

    # inserts a new certificate revocation list record
    # into an user database
    when ( 'CreateCRL' ) {
      my $crl_name = $params->{ 'name' } || '';
      my %options = map { +"$_" => $params->{ $_ } || '' } 
        qw( desc cacrt cakey );

      &create_crl( $R, $crl_name, %options );
    }

    # return a list of all certificate revocation lists
    when ( 'ListCRLs' ) {
      &list_crls( $R );
    }

    # remove a certificate revocation list
    when ( 'RemoveCRL' ) {
      my $crl_name = $params->{ 'name' } || '';

      &remove_crl( $R, $crl_name );
    }

    # removes all certificate revocation lists 
    # from an user database
    when ( 'RemoveAllCRLs' ) {
      &remove_all_crls( $R );
    }

    # returns serial for certificate generation
    when ( 'GetSerial' ) {
      &get_serial( $R );
    }

    # append a certificate to a CRL
    when ( 'AddToCRL' ) {
      my $crt_name = $params->{ 'name' } || '';
      my $crl_name = $params->{ 'crl'} || '';

      &add_crt_to_crl( $R, $crt_name, $crl_name );
    }

    # remove a certificate from a CRL
    when ( 'RemoveFromCRL' ) {
      my $crt_name = $params->{ 'name' } || '';
      my $crl_name = $params->{ 'crl'} || '';

      &remove_crt_from_crl( $R, $crt_name, $crl_name );
    }


    # deploy
    when ( 'Deploy' ) {
      my $name = $params->{ 'name' } || '';
      my $host = $params->{ 'host' } || 'localhost';

      &deploy( $R, $name, $host );
    }

    # export
    when ( 'Export' ) {
      &send_error( $R, &NOT_IMPLEMENTED() );
    }


    # wrong input data
    default {
      &send_error( $R, &NOT_IMPLEMENTED() );
    }
  }

  return;
}


=item B<send_error>( $feersum, $error_code, [ $msg ] )

Sends a response with an error code $error_code.

Currently implemented error codes:

=over

=item 0 NO_ERROR

There is no any error.

=item 1 BAD_REQUEST

Bad request from a client.

=item 2 NOT_IMPLEMENTED

Requested service is not implemented yet.

=item 3 INTERNAL_ERROR

Some sort of an internal error has occurs on a server side.

=item 4 INVALID_NAME

Invalid name. Usually, name is a key in a database.

=item 5 DUPLICATE_ENTRY

Duplicate entry in a database.

=item 6 ENTRY_NOT_FOUND

An entry not found in a database.

=item 7 MISSING_DATABASE

The target database name was not found.

=back

=cut


sub send_error($$;$) {
  my ( $R, $code, $msg ) = @_;


  my %data = ( err => $code );
  $data{ 'msg' } = decode_utf8 ($msg) if ( $msg );

  my $w = $R->start_streaming (200, \@HEADER_JSON);
  $w->write (encode_json (\%data));
  $w->close ();

  return;
}


=item B<send_response>( $feersum, %data )

Sends a response with a specified data %data. The repsonse
will be encoded as JSON.

=cut


sub send_response($%) {
  my ( $R, %data ) = @_;


  my $w = $R->start_streaming( 200, \@HEADER_JSON );
  $w->write( encode_json( \%data ) );
  $w->close();

  return;
}


=item B<genkey>( $feersum, $name, $type, $bits, [ $cipher, $password ] )

Generates a private key, where are $name is a filename,
$type is either RSA or DSA, $bits is one of the next values: 1024, 2048, 4096.
To create an encrypted private key the additional arguments should be
passed: $cipher is one of DES3, AES128, AES192, AES256; $password is 
a passphrase.

=cut


sub genkey($$$$;$$) {
  my ( $R, $name, $type, $bits, $cipher, $password ) = @_;


  if ( not &check_file_name( $name ) ) {
    &send_error( $R, &INVALID_NAME() );
    return;
  }

  my %types =
    (
      'RSA' => 'genrsa',
      #'DSA' => 'gendsa'
    )
  ;
  my %ciphers = 
    (
      'DES3'    => '-des3',
      'AES128'  => '-aes128',
      'AES192'  => '-aes192',
      'AES256'  => '-aes256',
    )
  ;
  my @command = ( 'openssl' );
  my @fdsetup = 
    (
      "<", "/dev/null",
      ">", \my $stdout,
      "2>", \my $stderr,
      "4>", \my $keyout,
    )
  ;  

  if ( exists $types{ $type } ) {
    push @command, $types{ $type };
  } else {
    &send_error( $R, &BAD_REQUEST() );
    return;
  }

  if ( $cipher && $password ) {
    if ( exists $ciphers{ $cipher } ) {
      push @command, $ciphers{ $cipher }, '-passout', 'fd:3';
      push @fdsetup, "3<", \$password;
    } else {
      &send_error( $R, &BAD_REQUEST() );
      return;
    }

    if ( ! check_password( $password ) ) {
      &send_error( $R, &BAD_REQUEST() );
      return;      
    }
  }

  if ( $bits >= 1024 ) {
    push @command, '-out', '/dev/fd/4';
  } else {
    &send_error( $R, &BAD_REQUEST() );
    return;
  }
  
  if ( $type eq 'RSA' ) {
    push @command, $bits;
  } else {
    # TODO
    # using pre-generate dsaparam files?
    # e.g., openssl dsaparam -out dsaparam2048 -genkey 2048
    push @command, 'dsaparam' . $bits;
  }
  
  my $cv = run_cmd [ @command ], @fdsetup;

  $cv->cb( sub {
    &Scalar::Util::weaken( my $R = $R );

    # check if command executed successfully
    shift->recv()
      and return &send_error( $R, &INTERNAL_ERROR(), $stderr );

    # find out a database name to store result
    my $maindb = Local::DB::UnQLite->new( '__db__' );
    my $dbname = $maindb->fetch( '_' )
      || return &send_error( $R, &MISSING_DATABASE() );

    # checks if database settings record exists
    $maindb->fetch( $dbname )
      or return &send_error( $R, &MISSING_DATABASE() );

    my $db = Local::DB::UnQLite->new( $dbname );

    # checks if a key already generated for specified $name
    my $pkeyname = 'key_' . $name;

    $db->fetch( $pkeyname )
      and return &send_error( $R, &DUPLICATE_ENTRY() );

    my %data =
      (
        name    => $name,
        size    => $bits,
        type    => $type,
        cipher  => $cipher,
        passwd  => $password ? 'secret' : '',
        out     => $keyout,
      )
    ;

    $db->store( $pkeyname, encode_json( \%data ) )
      ? &send_response( $R, 'name', $name )
      : &send_error( $R, &INTERNAL_ERROR() );
  } );

  return;
}


=item B<check_password>( $password )

Checks a password length. By default a minimum is 4 symbols
and a maximum is 8192 symbols.

Returns true (1) on success, otherwise returns false (0).

=cut


{
  my $min = 4;
  my $max = 8192;

  # Check for a length of $pass was added because of
  # running the command below by a hand does this check.
  #
  # No need to call fork() for obvious result.

  sub check_password($) {
    my ( $password ) = @_;


    my $length = length( $password || '' );
    
    if ( $length >= $min && $length < $max ) {
      return 1;
    } else {
      return 0;
    }
  }

}


=item B<check_days>( $days )

Checks a days parameter.

=cut


sub check_days($) {
  my ( $days ) = @_;


  $days =~ m/^\d+$/o or return 0;

  return ( $days >= 1 );
}


=item B<create_db>( $feersum, $name, $description )

Adds new database record with the key $name to an 
internal database '__db__'.

=cut


sub create_db($$$) {
  my ( $R, $name, $desc ) = @_;


  if ( not &check_db_name( $name ) ) {
    &send_error( $R, &INVALID_NAME() );
    return;
  }

  my $dbs = Local::DB::UnQLite->new( '__db__' );

  if ( not $dbs->fetch( $name ) ) {
    my %data = ( name => $name, desc => $desc );
    $dbs->store( $name, encode_json( \%data ) )
      or return &send_error( $R, &INTERNAL_ERROR() );

    # set initial serial number for certificates
    my $db = Local::DB::UnQLite->new( $name );
    $db->store( 'serial', 1 )
      ? &send_response( $R, 'name', $name )
      : &send_error( $R, &INTERNAL_ERROR(), 'store serial' );
  } else {
    &send_error( $R, &DUPLICATE_ENTRY() );
    return;
  }

  return;
}


=item B<remove_db>( $feersum, $name, $description )

Removes a database record with the key $name from an 
internal database '__db__'.

=cut


sub remove_db($$) {
  my ( $R, $name ) = @_;


  if ( not &check_db_name( $name ) ) {
    &send_error( $R, &INVALID_NAME() );
    return;
  }

  my $dbs = Local::DB::UnQLite->new( '__db__' );

  if ( $dbs->fetch( $name ) ) {
    if ( my $active = $dbs->fetch( '_' ) ) {
      if ( $active eq $name ) {
        $dbs->delete( '_' );
      }

      &Local::DB::UnQLite::closedb( $name );
    }

    $dbs->delete( $name )
      ? &send_response( $R, 'name', $name )
      : &send_error( $R, &INTERNAL_ERROR() );
  } else {
    &send_error( $R, &ENTRY_NOT_FOUND() );
    return;
  }

  return;
}


=item B<update_db>( $feersum, $name, $description )

Updates an existing database record with the key $name 
in an internal database '__db__'. The value name is kept
as it was before, i.e. never updates.

=cut


sub update_db($$$) {
  my ( $R, $name, $desc ) = @_;


  if ( not &check_db_name( $name ) ) {
    &send_error( $R, &INVALID_NAME() );
    return;
  }

  my $dbs = Local::DB::UnQLite->new( '__db__' );

  if ( my $data = $dbs->fetch_json( $name ) ) {
    $data->{ 'desc' } = $desc;
    $dbs->store( $name, encode_json( $data ) )
      ? &send_response( $R, 'name', $name )
      : &send_error( $R, &INTERNAL_ERROR() );
  } else {
    &send_error( $R, &ENTRY_NOT_FOUND() );
    return;
  }

  return;
}


=item B<switch_db>( $feersum, $name )

Sets the key '_' with a specified database name $name 
in an internal database '__db__'. All next non-database management
related actions will be performed using the specified
database with the name $name.

The database record with a specified $name must be
created before calling this function.

=cut


sub switch_db($$) {
  my ( $R, $name ) = @_;


  if ( not &check_db_name( $name ) ) {
    &send_error( $R, &INVALID_NAME() );
    return;
  }

  # Close all database handlers to prevent
  # multiple open database handlers.
  &Local::DB::UnQLite::closealldb();

  my $dbs = Local::DB::UnQLite->new( '__db__' );

  if ( $dbs->fetch( $name ) ) {
    $dbs->store( '_', $name )
      ? &send_response( $R, 'name', $name )
      : &send_error( $R, &INTERNAL_ERROR() );
  } else {
    &send_error( $R, &ENTRY_NOT_FOUND() );
    return;
  }

  return;
}


=item B<current_db>( $feersum )

Sends a response to a client side with a name of the
current active database. See also B<switch_db>()
for details.

=cut


sub current_db($) {
  my ( $R ) = @_;


  my $dbs = Local::DB::UnQLite->new( '__db__' );

  if ( my $name = $dbs->fetch( '_' ) ) {
    &send_response( $R, 'name', $name );
  } else {
    &send_error( $R, &ENTRY_NOT_FOUND() );
    return;
  }

  return;  
}


=item B<list_dbs>( $feersum )

Sends a response to client side with list of databases.

=cut


sub list_dbs($) {
  my ( $R ) = @_;


  my $dbs = Local::DB::UnQLite->new ('__db__');
  my $all = $dbs->all_json_except ('_');

  &send_response ($R, 'dbs', $all);
}


=item B<remove_all_dbs>( $feersum )

Removes all entries from an internal database '__db__'.

=cut


sub remove_all_dbs($) {
  my ( $R ) = @_;


  my $dbs = Local::DB::UnQLite->new ('__db__');
  my @keys = $dbs->keys();
  my $num = $dbs->delete_all();

  &Local::DB::UnQLite::closealldb ();
  &Local::DB::UnQLite::deletedb ($_) for @keys;

  &send_response ($R, 'deleted', $num);
}


=item B<check_db_name>( $name )

Performs a test if a specified database name $name is
valid. There are exists reserved names: '_', '__db__'.

The name $name may contents alphanumeric characters and
next symbols: '.', '-', '+', '_'.

=cut


sub check_db_name($) {
  my ( $name ) = @_;


  my %reserved = ( '_' => 1, '__db__' => 1 );
  exists $reserved{ $name } and return 0;

  return ( $name =~ m/^[\w\.\-\+\_]+$/o );
}


=item B<check_file_name>( $name )

Performs a test if a specified file name $name is a valid.

The name $name may contents alphanumeric characters and
next symbols: '-', '_', '.'.

A length of a name must be between 1 and 128 symbols.

=cut


sub check_file_name($) {
  my ( $name ) = @_;


  my $length = length( $name );

  if ( $length >= 1 && $length <= 128 ) {
    return ( $name =~ m/^[\w\-\.\_]+$/o );
  } else {
    return 0;
  }
}


=item B<check_dir_name>( $name )

Performs a test if a specified directory name $name is a valid.

The name $name may contents alphanumeric characters and
next symbols: '-', '_'.

A length of a name must be between 1 and 128 symbols.

=cut


sub check_dir_name($) {
  my ( $name ) = @_;


  my $length = length( $name );

  if ( $length >= 1 && $length <= 128 ) {
    return ( $name =~ m/^[\w\-\_]+$/o );
  } else {
    return 0;
  }
}


=item B<remove_key>( $feersum, $name )

Removes from a database a private key with specified name $name.

=cut


sub remove_key($$) {
  my ( $R, $name ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $kv = 'key_' . $name;

  $db->fetch( $kv )
    or return &send_error( $R, &ENTRY_NOT_FOUND() );

  $db->delete( $kv )
    ? &send_response( $R, 'name', $name )
    : &send_error( $R, &INTERNAL_ERROR() );
}


=item B<list_keys>( $feersum )

Sends to a client side a list of private keys.

=cut


sub list_keys($) {
  my ( $R ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $items = $db->like_json( '^key_' );

  # sanitize key text data
  delete $_->{ 'out' } for ( @$items );

  &send_response( $R, 'keys', $items );
}


=item B<remove_all_keys>( $feersum )

Removes all private keys entries from a database.

=cut


sub remove_all_keys($) {
  my ( $R ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $num = $db->delete_like( '^key_' );

  &send_response( $R, 'deleted', $num );
}


=item B<gencsr>( $feersum, $name, %options )

Generates a new certificate request. A list of valid options:

  keyname => $keyname,
  subject => $subject,
  keypass => $keypass,    # optional
  digest  => $digest,     # optional

=cut


sub gencsr($$%) {
  my ( $R, $name, %options ) = @_;


  if ( not &check_file_name( $name ) ) {
    &send_error( $R, &INVALID_NAME(), 'name' );
    return;
  }

  if ( not &check_file_name( $options{ 'keyname' } ) ) {
    &send_error( $R, &INVALID_NAME(), 'keyname' );
    return;
  }

  my @command = 
    ( 
      'openssl',
      'req',
      '-batch',
      '-new',
      '-key', '/dev/fd/3', 
      '-out', '/dev/fd/4',
    )
  ;
  my @fdsetup = 
    (
      "<", "/dev/null",
      ">", \my $stdout,
      "2>", \my $stderr,
      "4>", \my $csrout,
    )
  ;

  push @command, '-subj', $options{ 'subject' };
  push @command, '-passin', 'fd:5';

  if ( my $keypass = $options{ 'keypass' } ) {
    if ( &check_password( $keypass ) ) {
      push @fdsetup, "5<", \$keypass;
    } else {
      &send_error( $R, &BAD_REQUEST() );
      return;
    }
  } else {
    my $passwd = 'test';
    push @fdsetup, "5<", \$passwd;
  }

  if ( my $digest = $options{ 'digest' } ) {
    if ( exists $DIGESTS{ $digest } ) {
      push @command, $DIGESTS{ $digest };
    } else {
      &send_error( $R, &BAD_REQUEST(), 'digest' );
      return;
    }  
  }

  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $kv = 'key_' . $options{ 'keyname' };
  my $entry = $db->fetch_json( $kv )
    or return &send_error( $R, &ENTRY_NOT_FOUND() );

  my $keyin = $entry->{ 'out' }
    or return &send_error( $R, &INTERNAL_ERROR(), "key out");
  push @fdsetup, "3<", \$keyin;


  my $cv = run_cmd [ @command ], @fdsetup;

  $cv->cb( sub {
    &Scalar::Util::weaken( my $R = $R );

    # check if command executed successfully
    shift->recv()
      and return &send_error( $R, &INTERNAL_ERROR(), $stderr );

    # find out a database name to store result
    my $maindb = Local::DB::UnQLite->new( '__db__' );
    my $dbname = $maindb->fetch( '_' )
      || return &send_error( $R, &MISSING_DATABASE() );

    # checks if database settings record exists
    $maindb->fetch( $dbname )
      or return &send_error( $R, &MISSING_DATABASE() );

    my $db = Local::DB::UnQLite->new( $dbname );

    # checks if a csr already generated for specified $name
    my $csrname = 'csr_' . $name;

    $db->fetch( $csrname )
      and return &send_error( $R, &DUPLICATE_ENTRY() );

    my %data =
      (
        name    => $name,
        keyname => $options{ 'keyname' },
        keypass => $options{ 'keypass' } ? 'secret' : '',
        subject => $options{ 'subject' },
        digest  => $options{ 'digest' },
        out     => $csrout,
      )
    ;

    $db->store( $csrname, encode_json( \%data ) )
      ? &send_response( $R, 'name', $name )
      : &send_error( $R, &INTERNAL_ERROR() );
  } );

  return;
}


=item B<list_csrs>( $feersum )

Sends to a client side a list of certificate signing requests.

=cut


sub list_csrs($) {
  my ( $R ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $items = $db->like_json( '^csr_' );

  # sanitize
  delete $_->{ 'out' } for ( @$items );

  &send_response( $R, 'csrs', $items );
}


=item B<remove_csr>( $feersum, $name )

Removes from a database a certificate signing request with specified name $name.

=cut


sub remove_csr($$) {
  my ( $R, $name ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $kv = 'csr_' . $name;

  $db->fetch( $kv )
    or return &send_error( $R, &ENTRY_NOT_FOUND() );

  $db->delete( $kv )
    ? &send_response( $R, 'name', $name )
    : &send_error( $R, &INTERNAL_ERROR() );
}


=item B<remove_all_csrs>( $feersum )

Removes all certificate signing requests entries from a database.

=cut


sub remove_all_csrs($) {
  my ( $R ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $num = $db->delete_like( '^csr_' );

  &send_response( $R, 'deleted', $num );
}


=item B<gencrt>( $feersum, $name, %params )

Generates a new certificate.
An example of an options %params for a common certificate:

  keyname => $keyname,    # private key
  keypass => $keypass,    # optional
  days    => $days,
  subject => $subject,    # optional
  digest  => $digest,     # optional

An example of an options %params for a self-signed certificate:

  csrname => $csrname,    # csr name
  days    => $days,
  cacrt   => $ca_crt,     # CA certificate name
  cakey   => $ca_key,     # CA certificate key name
  cakeypw => $ca_key_pw,  # CA certificate passsword, optional


=cut 


sub gencrt($$%) {
  my ( $R, $name, %params ) = @_;


  if ( not &check_file_name( $name ) ) {
    &send_error( $R, &INVALID_NAME(), 'certificate name' );
    return;
  }

  if ( not &check_days( $params{ 'days' } ) ) {
    &send_error( $R, &BAD_REQUEST(), 'invalid value for days' );
    return;
  }


  my @command = ( 'openssl' );
  my @fdsetup = 
    (
      "<",  "/dev/null",
      ">",  \my $stdout,
      "2>", \my $stderr,
      "3>", \my $crtout,
    )
  ;

  my $isSelfSign = 0;

  if ( $params{ 'csrname' } ) {
    # set the self-signed certificate flag to use it later
    $isSelfSign = 1;

    for my $filename ( qw( csrname cacrt cakey ) ) {
      &check_file_name( $params{ $filename } ) and next;
      &send_error( $R, &INVALID_NAME(), "incorrect name for $filename" );
      return;
    }

    push @command,
      'x509',       '-req',
      '-out',       '/dev/fd/3',
      '-in',        '/dev/fd/4', # csr
      '-CA',        '/dev/fd/5', # ca crt
      '-CAkey',     '/dev/fd/6', # ca key
      '-passin',    'fd:8',
    ;

    # + passin
    if ( my $passwd = $params{ 'cakeypw' } ) {
      if ( &check_password( $passwd ) ) {
        push @fdsetup, '8<', \$passwd;
      } else {
        &send_error( $R, &BAD_REQUEST() );
        return;
      }
    } else {
      my $passwd = 'test';
      push @fdsetup, '8<', \$passwd;
    }

    # TODO digest?
    # possible options: -md2|-md5|-sha1|-mdc2
    # default is SHA1

  } else {
    # common certificate
    if ( not &check_file_name( $params{ 'keyname' } ) ) {
      &send_error( $R, &INVALID_NAME() );
      return;
    }

    push @command,
      'req',      '-batch',
      '-new',     '-x509',
      '-out',     '/dev/fd/3',
      '-key',     '/dev/fd/4',
      '-passin',  'fd:5',
    ;

    # + subject
    if ( $params{ 'subject' } ) {
      push @command, '-subj', $params{ 'subject' };
    }

    # + passin
    if ( my $passwd = $params{ 'keypass' } ) {
      if ( &check_password( $passwd ) ) {
        push @fdsetup, '5<', \$passwd;
      } else {
        &send_error( $R, &BAD_REQUEST() );
        return;
      }
    } else {
      my $passwd = 'test';
      push @fdsetup, '5<', \$passwd;
    }

    # + digest

    if ( my $digest = $params{ 'digest' } ) {
      if ( exists $DIGESTS{ $digest } ) {
        push @command, $DIGESTS{ $digest };
      } else {
        &send_error( $R, &BAD_REQUEST() );
        return;
      }
    }
  }

  # + days
  push @command, '-days', $params{ 'days' };

  # open a database for neccessary data 
  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );

  # + set_serial
  my $serial = $db->fetch( 'serial' )
    or return &send_error( $R, &INTERNAL_ERROR(), 'missing serial' );
  push @command, '-set_serial', $serial;


  # retrieving neccessary keys and certs.
  if ( $isSelfSign ) {
    # -in csr
    my $kv_csr = 'csr_' . $params{ 'csrname' };
    my $csr = $db->fetch_json( $kv_csr )
      or return &send_error( $R, &ENTRY_NOT_FOUND() );
    my $csrin = $csr->{ 'out' }
      or return &send_error( $R, &INTERNAL_ERROR(), "missing csr" );
    push @fdsetup, "4<", \$csrin;

    # -CA
    my $kv_ca_crt = 'crt_' . $params{ 'cacrt' };
    my $crt = $db->fetch_json( $kv_ca_crt )
      or return &send_error( $R, &ENTRY_NOT_FOUND() );
    my $crtin = $crt->{ 'out' }
      or return &send_error( $R, &INTERNAL_ERROR(), "missing ca crt" );
    push @fdsetup, "5<", \$crtin;

    # -CAkey
    my $kv_ca_key = 'key_' . $params{ 'cakey' };
    my $key = $db->fetch_json( $kv_ca_key )
      or return &send_error( $R, &ENTRY_NOT_FOUND() );
    my $keyin = $key->{ 'out' }
      or return &send_error( $R, &INTERNAL_ERROR(), "missing ca key" );
    push @fdsetup, "6<", \$keyin;

  } else {
    # -key
    my $kv = 'key_' . $params{ 'keyname' };
    my $key = $db->fetch_json( $kv )
      or return &send_error( $R, &ENTRY_NOT_FOUND(), 'invalid keyname?' );

    my $keyin = $key->{ 'out' }
      or return &send_error( $R, &INTERNAL_ERROR(), "missing key" );

    push @fdsetup, "4<", \$keyin;
  }

  my $cv = run_cmd [ @command ], @fdsetup;

  $cv->cb( sub {
    &Scalar::Util::weaken( my $R = $R );

    # check if command executed successfully
    shift->recv()
      and return &send_error( $R, &INTERNAL_ERROR(), $stderr );

    # find out a database name to store result
    my $maindb = Local::DB::UnQLite->new( '__db__' );
    my $dbname = $maindb->fetch( '_' )
      || return &send_error( $R, &MISSING_DATABASE() );

    # checks if database settings record exists
    $maindb->fetch( $dbname )
      or return &send_error( $R, &MISSING_DATABASE() );

    my $db = Local::DB::UnQLite->new( $dbname );    
    my $kv = 'crt_' . $name;

    # checks if a crt already generated for specified $name
    $db->fetch( $kv )
      and return &send_error( $R, &DUPLICATE_ENTRY() );

    my %data =
      (
        name      => $name,
        desc      => $params{ 'desc' },
        days      => $params{ 'days' },
        serial    => $serial,
        template  => $params{ 'template' },
        incrl     => [ ],
        out       => $crtout,
      )
    ;

    if ( $isSelfSign ) {
      $data{ 'csrname' }  = $params{ 'csrname' };
      $data{ 'cacrt' }    = $params{ 'cacrt' };
      $data{ 'cakey' }    = $params{ 'cakey' };
      $data{ 'cakeypw' }  = $params{ 'cakeypw' } ? 'secret' : '';
    } else {
      $data{ 'keyname' }  = $params{ 'keyname' };
      $data{ 'keypass' }  = $params{ 'keypass' } ? 'secret' : '';
      $data{ 'subject' }  = $params{ 'subject' };
      $data{ 'digest' }   = $params{ 'digest' };
    }

    $db->store( 'serial', ++$serial )
      or return &send_error( $R, &INTERNAL_ERROR(), 'store serial' );

    $db->store( $kv, encode_json( \%data ) )
      ? &send_response( $R, 'name', $name )
      : &send_error( $R, &INTERNAL_ERROR() );
  } );

  return;
}


=item B<list_crts>( $feersum )

Sends to a client side a list of certificates.

=cut


sub list_crts($) {
  my ( $R ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $items = $db->like_json( '^crt_' );

  # sanitize
  delete $_->{ 'out' } for ( @$items );

  &send_response( $R, 'crts', $items );
}


=item B<remove_crt>( $feersum, $name )

Removes from a database a certificate with specified name $name.

=cut


sub remove_crt($$) {
  my ( $R, $name ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $kv = 'crt_' . $name;

  my $entry = $db->fetch_json( $kv )
    or return &send_error( $R, &ENTRY_NOT_FOUND(), 'fetch kv' );
  my $this_serial = $entry->{ 'serial' }
    or return &send_error( $R, &INTERNAL_ERROR(), 'invalid serial' );

  # descrease serial number if removing last inserted entry
  my $serial = $db->fetch( 'serial' )
    or return &send_error( $R, &INTERNAL_ERROR(), 'fetch serial' );

  if ( $serial - $this_serial == 1 ) {
    $db->store( 'serial', $this_serial )
      or return &send_error( $R, &INTERNAL_ERROR(), 'store serial' );
  }

  $db->delete( $kv )
    ? &send_response( $R, 'name', $name )
    : &send_error( $R, &INTERNAL_ERROR() );
}


=item B<remove_all_crts>( $feersum )

Removes all certificates entries from a database.

=cut


sub remove_all_crts($) {
  my ( $R ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $num = $db->delete_like( '^crt_' );

  # reset serial
  $db->store( 'serial', 1 )
    ? &send_response( $R, 'deleted', $num )
    : &send_error( $R, &INTERNAL_ERROR(), 'store serial' );
}


=item B<create_crl>( $feersum, $name, %options )

Creates a new certificate revocation list record into a database.
A list of valid options:

  desc  => $description,
  cacrt => $ca_crt_name,
  cakey => $ca_key_name,

=cut


sub create_crl($$%) {
  my ( $R, $name, %options ) = @_;


  if ( not &check_file_name( $name ) ) {
    &send_error( $R, &INVALID_NAME(), 'name' );
    return;
  }

  if ( not &check_file_name( $options{ 'cacrt' } ) ) {
    &send_error( $R, &INVALID_NAME(), 'cacrt' );
    return;
  }

  if ( not &check_file_name( $options{ 'cakey' } ) ) {
    &send_error( $R, &INVALID_NAME(), 'cakey' );
    return;
  }


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $kv = 'crl_' . $name;

  # checks if a crl already generated for specified $name
  $db->fetch( $kv )
    and return &send_error( $R, &DUPLICATE_ENTRY() );

  my %data =
    (
      name  => $name,
      desc  => $options{ 'desc' },
      cacrt => $options{ 'cacrt' },
      cakey => $options{ 'cakey' },
    )
  ;

  $db->store( $kv, encode_json( \%data ) )
    ? &send_response( $R, 'name', $name )
    : &send_error( $R, &INTERNAL_ERROR() );
}


=item B<gencrl>( $feersum, $crl_name, [ $cakeypw ] )

Generates a certificate revocation list file.

=cut


sub gencrl($$;$) {
  my ( $R, $crl_name, $cakeypw ) = @_;


  &send_error( $R, &NOT_IMPLEMENTED() );
}


=item B<list_crls>( $feersum )

Sends to a client side a list of certificate revocation lists.

=cut


sub list_crls($) {
  my ( $R ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $items = $db->like_json( '^crl_' );

  # sanitize
  delete $_->{ 'out' } for ( @$items );

  &send_response( $R, 'crls', $items );
}


=item B<remove_crl>( $feersum, $name )

Removes from a database a certificate revocation lists with specified name $name.

=cut


sub remove_crl($$) {
  my ( $R, $name ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $kv = 'crl_' . $name;

  $db->fetch( $kv )
    or return &send_error( $R, &ENTRY_NOT_FOUND() );

  $db->delete( $kv )
    ? &send_response( $R, 'name', $name )
    : &send_error( $R, &INTERNAL_ERROR() );
}


=item B<remove_all_crls>( $feersum )

Removes all certificate revocation lists entries from a database.

=cut


sub remove_all_crls($) {
  my ( $R ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $num = $db->delete_like( '^crl_' );

  &send_response( $R, 'deleted', $num );
}


=item B<get_serial>( $feersum )

Returns current next serial number to generate a certificate.
If no databases were activated returns an error.

=cut


sub get_serial($) {
  my ( $R ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $serial = $db->fetch( 'serial' );

  defined $serial
    ? &send_response( $R, 'serial', $serial )
    : &send_error( $R, &INTERNAL_ERROR(), 'invalid serial' );
}


=item B<add_crt_to_crl>( $feersum, $crt_name, $crl_name )

Adds a certificate with name $crt_name to a CRL with name $crl_name.

=cut


sub add_crt_to_crl($$$) {
  my ( $R, $crt_name, $crl_name ) = @_;


  if ( not &check_file_name( $crt_name ) ) {
    &send_error( $R, &INVALID_NAME(), 'invalid crt name' );
    return;
  }

  if ( not &check_file_name( $crl_name ) ) {
    &send_error( $R, &INVALID_NAME(), 'invalid crl name' );
    return;
  }


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $crl = $db->fetch_json( 'crl_' . $crl_name )
    or return &send_error( $R, &INTERNAL_ERROR(), 'crl is missing' );

  my $crt = $db->fetch_json( 'crt_' . $crt_name )
    or return &send_error( $R, &INTERNAL_ERROR(), 'crt is missing' );


  if ( ref $crt->{ 'incrl' } eq 'ARRAY' ) {
    # check if crt already has a crl record
    my $list = $crt->{ 'incrl' };
    my %crls = map { +"$_" => 1 } @{ $list };

    if ( exists $crls{ $crl_name } ) {
      &send_error( $R, &INTERNAL_ERROR(), 'already added to this CRL' );
      return;
    }

    # add crl name
    push @$list, $crl_name;

  } else {
    # create array if needed
    my @list = ( $crl_name );
    $crt->{ 'incrl' } = \@list;

  }

  # update record
  $db->store( 'crt_' . $crt_name, encode_json( $crt ) )
    ? &send_response( $R, 'name', $crt_name )
    : &send_error( $R, &INTERNAL_ERROR(), 'failed to store crt' );
}


=item B<remove_crt_from_crl>( $feersum, $crt_name, $crl_name )

Removes a certificate with name $crt_name from a CRL with name $crl_name.

=cut


sub remove_crt_from_crl($$$) {
  my ( $R, $crt_name, $crl_name ) = @_;


  if ( not &check_file_name( $crt_name ) ) {
    &send_error( $R, &INVALID_NAME(), 'invalid crt name' );
    return;
  }

  if ( not &check_file_name( $crl_name ) ) {
    &send_error( $R, &INVALID_NAME(), 'invalid crl name' );
    return;
  }


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $crl = $db->fetch_json( 'crl_' . $crl_name )
    or return &send_error( $R, &INTERNAL_ERROR(), 'crl is missing' );

  my $crt = $db->fetch_json( 'crt_' . $crt_name )
    or return &send_error( $R, &INTERNAL_ERROR(), 'crt is missing' );


  if ( ref $crt->{ 'incrl' } eq 'ARRAY' ) {
    # check if crt already has a crl record
    my $list = $crt->{ 'incrl' };
    my %crls = map { +"$_" => 1 } @{ $list };

    if ( exists $crls{ $crl_name } ) {
      delete $crls{ $crl_name };
      @$list = keys %crls;
    } else {
      &send_error( $R, &INTERNAL_ERROR(), 'crl not found' );
      return;
    }

  } else {
    # create an empty list
    $crt->{ 'incrl' } = [ ];

  }

  # update record
  $db->store( 'crt_' . $crt_name, encode_json( $crt ) )
    ? &send_response( $R, 'name', $crt_name )
    : &send_error( $R, &INTERNAL_ERROR(), 'failed to store crt' );
}


=item B<deploy>( $feersum, $name, $host, [ $ca_key_password ] )

Deploy certificates with directory name $name on host $host.

=cut


sub deploy($$$;$) {
  my ( $R, $name, $host, $ca_pass ) = @_;


  if ( not &check_dir_name( $name ) ) {
    &send_error( $R, &INVALID_NAME(), 'invalid name' );
    return;
  }

  my $dir = catdir( &get_setting( 'DEPLOY_DIR' ), $name );

  AE::log info => "deploying to \`%s\'", $dir;

  if ( -e $dir ) {
    -d $dir 
      or return &send_error( $R, &INVALID_NAME(), "$dir: $!" );

    # TODO cleanup files
  } else {
    AE::log debug => "creating directory \`%s\'", $dir;
    mkdir ( $dir, 0700 )
      or return &send_error( $R, &INTERNAL_ERROR(), "mkdir $dir: $!" );
  }

  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my %data = 
    (
      name => $name,
      path => $dir,
      keys => \my @keys_files,
      csrs => \my @csrs_files,
      crts => \my @crts_files,
    );

  my $keys = $db->like_json( '^key_' );
  for my $key ( values @$keys ) {
    my $filename = catfile( $dir, join( '.', $key->{ 'name' }, 'key' ) );

    open( my $fh, ">:raw", $filename )
      or return &send_error( $R, &INTERNAL_ERROR(), "open $filename: $!" );
    syswrite( $fh, $key->{ 'out' } )
      or return &send_error( $R, &INTERNAL_ERROR(), "write $filename: $!" );
    close( $fh )
      or return &send_error( $R, &INTERNAL_ERROR(), "close $filename: $!" );

    push @keys_files, $filename;
    AE::log debug => "created key file: %s", $filename;
  }

  my $csrs = $db->like_json( '^csr_' );
  for my $csr ( values @$csrs ) {
    my $filename = catfile( $dir, join( '.', $csr->{ 'name' }, 'csr' ) );

    open( my $fh, ">:raw", $filename )
      or return &send_error( $R, &INTERNAL_ERROR(), "open $filename: $!" );
    syswrite( $fh, $csr->{ 'out' } )
      or return &send_error( $R, &INTERNAL_ERROR(), "write $filename: $!" );
    close( $fh )
      or return &send_error( $R, &INTERNAL_ERROR(), "close $filename: $!" );

    push @csrs_files, $filename;
    AE::log debug => "created CSR file: %s", $filename;
  }

  my %crl_data;
  my $crts = $db->like_json( '^crt_' );
  for my $crt ( values @$crts ) {
    my $filename = catfile( $dir, join( '.', $crt->{ 'name' }, 'crt' ) );

    open( my $fh, ">:raw", $filename )
      or return &send_error( $R, &INTERNAL_ERROR(), "open $filename: $!" );
    syswrite( $fh, $crt->{ 'out' } )
      or return &send_error( $R, &INTERNAL_ERROR(), "write $filename: $!" );
    close( $fh )
      or return &send_error( $R, &INTERNAL_ERROR(), "close $filename: $!" );

    push @crts_files, $filename;
    AE::log debug => "created CRT file: %s", $filename;

    for my $crl_name ( @{ $crt->{ 'incrl' } } ) {
      if ( exists $crl_data{ $crl_name } ) {
        push @{ $crl_data{ $crl_name } }, $filename;
      } else {
        $crl_data{ $crl_name } = [ $filename ];
      }
    }
  }

  # generate a CRL file
  my $crls = $db->like_json( '^crl_' );

  for my $crl ( values @$crls ) {
    my $name = $crl->{ 'name' };

    next unless exists $crl_data{ $name };

    my $filename = catfile( $dir, join( '.', $name, 'pem' ) );
    my $ca_crt = catfile( $dir, join( '.', $crl->{ 'cacrt' }, 'crt' ) );
    my $ca_key = catfile( $dir, join( '.', $crl->{ 'cakey' }, 'key' ) );

    next if @{ $crl_data{ $name } } == 0;

    my $cfg = Local::OpenSSL::Conf->new( target_directory => $dir );
    my $cfg_file = $cfg->generate()
      or return &send_error( $R, &INTERNAL_ERROR(), $cfg->error() );

    AE::log trace => "openssl.conf: %s", $cfg_file;
    AE::log trace => &readfile( $cfg_file );

    my $sh = new Local::OpenSSL::Script::Revoke
        'target_directory'  => $dir,
        'crts'              => $crl_data{ $name },
        'ca_key'            => $ca_key,
        'ca_crt'            => $ca_crt,
        'crl_file'          => $filename,
        'config_file'       => $cfg_file,
    ;
    my $sh_file = $sh->generate()
      or return &send_error( $R, &INTERNAL_ERROR(), $sh->error() );

    AE::log trace => "revoke.sh: %s", $sh_file;
    AE::log trace => &readfile( $sh_file );

  }


  &send_response( $R, %data );
}


sub readfile {
  my ( $file ) = @_;


  if ( open( my $fh, "<:raw", $file ) ) {
    my $data = do { local $/; <$fh> };
    close( $fh ) and return $data;
    AE::log error => "close %s: %s", $file, $!;
    return;
  }

  AE::log error => "open %s: %s", $file, $!;
  return;
}

=back

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

(c) 2015-2016, Vitaliy V. Tokarev

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system itself.

=cut

\&app;
