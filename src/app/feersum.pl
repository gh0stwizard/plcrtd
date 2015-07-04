#!/usr/bin/perl

# 2015, Vitaliy V. Tokarev aka gh0stwizard vitaliy.tokarev@gmail.com
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as the Perl 5 programming language system itself.


=encoding utf-8

=head1 NAME

The application for the Feersum.

A modification for the plcrtd project.

=cut


use strict;
use common::sense;
use vars qw( $PROGRAM_NAME );
use AnyEvent;
use AnyEvent::Util;
use HTTP::Body ();
use JSON::XS qw( encode_json decode_json );
use Scalar::Util ();
use HTML::Entities ();
use Encode qw( decode_utf8 );
use Local::DB::UnQLite;


# body checks
my $MIN_BODY_SIZE = 4;
my $MAX_BODY_SIZE = 524288;

# read buffer size
my $RDBUFFSIZE = 32 * 1024;

# http headers for responses
my @HEADER_JSON = ( 'Content-Type' => 'application/json; charset=UTF-8' );

# FIXME
my @HEADER_P12 =
  ( 
    'Content-Type' => 'application/octet-stream',
    'Content-disposition' => 'attachment; filename=client.p12',
  )
;
my @HEADER_PEM =
  ( 
    'Content-Type' => 'application/octet-stream',
    'Content-disposition' => 'attachment; filename=client.pem',
  )
;

=head1 FUNCTIONS

=over 4

=cut


sub CONNECTION_ERROR  { 0 } # Connection error
sub BAD_REQUEST       { 1 } # Bad request
sub NOT_IMPLEMENTED   { 2 } # Not implemented
sub EINT_ERROR        { 3 } # Internal error
sub INVALID_NAME      { 4 } # Invalid entry name
sub DUPLICATE_ENTRY   { 5 } # Duplicate entry
sub ENTRY_NOTFOUND    { 6 } # Entry not found
sub MISSING_DATABASE  { 7 } # Missing target database name


=item B<app>( $request )

The main application function. Accepts one argument with
request object $request.

=cut


sub app {
  my ( $R ) = @_;

  my $env = $R->env();
  my $method = $env->{ 'REQUEST_METHOD' };

  if ( $method eq 'POST' ) {
    # POST methods
    my $type = $env->{ 'CONTENT_TYPE' };
    my $len = $env->{ 'CONTENT_LENGTH' };
    my $req = delete $env->{ 'psgi.input' };
    
    AE::log trace => "POST request: type = %s, length = %d",
      $type,
      $len,
    ;
    
    &do_post( $R, $req, $len, $type );

  } elsif ( $method eq 'GET' ) {
    # plcrtd does not using GET method
    _501( $R );

  } else {
    # unsupported method means 'cya!'
    _405( $R );

  }

  return;
}


=item B<get_params>( $request, $length, $content_type )

Reads HTTP request body. Returns hash reference with request parameters.
A key represents a name of parameter and it's value represents an actual value.

=cut


sub get_params($$$) {
  my ( $r, $len, $content_type ) = @_;

  # reject empty, small or very big requests
  ( ( $len < $MIN_BODY_SIZE ) || ( $len > $MAX_BODY_SIZE ) )
    and return;

  my $body = HTTP::Body->new( $content_type, $len );
  # cleanup all temp. files, including upload
  $body->cleanup( 1 );

  my $pos = 0;
  my $chunk = ( $len > $RDBUFFSIZE ) ? $RDBUFFSIZE : $len;

  while ( $pos < $len ) {
    $r->read( my $buf, $chunk ) or last;
    $body->add( $buf );
    $pos += $chunk;
  }

  $r->close();

  # FIXME
  my $result = $body->param();
  my $files = $body->upload();
  
#  use Data::Dumper;
#  AE::log trace => Dumper $files;
  
  for my $param ( keys %$files ) {
    my $size = $files->{ $param }{ 'size' };
    $size > 2048 and next;
    exists $result->{ $param } and next;
    my $file = $files->{ $param }{ 'tempname' };
    open( my $fh, "<", $file ) or next;
    $result->{ $param } = do { local $/; <$fh> };
    close( $fh );
  }

  return $result;
}


=item $json = B<do_post>( $feersum, $request, $length, $content_type )

Process a POST request.

=cut


sub do_post($$$$) {
  my $R = shift;
  my $params = &get_params( @_ )
    or &send_error( $R, &BAD_REQUEST() ), return;

  my $action = $params->{ 'action' } || '';

  my $min_pw_len = 4;
  my $max_pw_len = 8192;

  if ( $action eq 'listdbs' ) {
    # returns all database entries

    &list_dbs( $R );

  } elsif ( $action eq 'createdb' ) {
    # creates new database
    my $db_name = $params->{ 'name' } || '';
    my $db_desc = $params->{ 'desc' } || '';

    &create_db( $R, $db_name, $db_desc );

  } elsif ( $action eq 'removedb') {
    # removes a database and related files
    my $db_name = $params->{ 'name' } || '';

    &remove_db( $R, $db_name );

  } elsif ( $action eq 'switchdb' ) {
    # returns current database
    my $db_name = $params->{ 'name' } || '';

    &switch_db( $R, $db_name );

  } elsif ( $action eq 'updatedb' ) {
    # updates database settings
    my $db_name = $params->{ 'name' } || '';
    my $db_desc = $params->{ 'desc' } || '';

    &update_db( $R, $db_name, $db_desc );

  } elsif ( $action eq 'removealldb' ) {
    # removes all user database entries

    &remove_all_dbs( $R );

  } elsif ( $action eq 'currentdb' ) {
    # returns a name of current user database

    &current_db( $R );

  } elsif ( $action eq 'genkey' ) {
    # generates new private key and stores into user database
    my $name = $params->{ 'name' } || '';
    my $type = $params->{ 'type' } || 'RSA';
    my $bits = int( $params->{ 'bits' } || 0 );
    my $cipher = $params->{ 'cipher' } || '';
    my $passwd = $params->{ 'passwd' } || '';    

    &genpkey( $R, $name, $type, $bits, $cipher, $passwd );

  } elsif ( $action eq 'removekey' ) {
    # removes a private key from an user database
    my $name = $params->{ 'name' } || '';

    &remove_pkey( $R, $name );

  } elsif ( $action eq 'listkeys' ) {
    # return a list of all private keys

    &list_pkeys( $R );

  } elsif ( $action eq 'removeallkeys' ) {
    # removes all entries for private keys from an user database

    &remove_all_pkeys( $R );

  } elsif ( $action eq 'gencsr' ) {
    # generates new certificate requests and stores into user database
    my $name = $params->{ 'name' } || '';
    my $keyname = $params->{ 'keyname' } || '';
    my $subject = $params->{ 'subject' } || '/CN=plcrtd';
    my $keypass = $params->{ 'keypass' } || '';

    &gencsr( $R, $name, $keyname, $subject, $keypass );

  } elsif ( $action eq 'listcsrs' ) {
    # list of certificate requests

    &list_csrs( $R );

  } elsif ( $action eq 'removecsr' ) {
    # remove a certificate request
    my $name = $params->{ 'name' } || '';

    &remove_csr( $R, $name );

  } elsif ( $action eq 'removeallcsrs' ) {
    # removes all certificate requests from an user database

    &remove_all_csrs( $R );

  } elsif ( $action eq 'listcrts' ) {
    # return a list of all certificates

    &list_crts( $R );

  } elsif ( $action eq 'listcrls' ) {
    # return a list of all certificate revocation lists

    &list_crls( $R );

  } elsif ( $action eq 'genCAcrt' ) {
    my $key = $params->{ 'key' } || '';
    my $pass = $params->{ 'pass' } || '';
    my $days = int( $params->{ 'days' } || 0 );
    my $subj = $params->{ 'subj'} || '';

    my $pw_len = length( $pass );

    if ( $key ne '' && $subj ne ''
      && $pw_len >= $min_pw_len && $pw_len < $max_pw_len && $days > 0 )
    {
      my $cv = run_cmd [
        qw( openssl req -batch -new -x509 -days ), $days,
        qw( -key /dev/fd/3 -out /dev/fd/4 -passin fd:5 -subj ),
        $subj
      ],
        "<", "/dev/null",
        ">", \my $stdout,
        "2>", \my $stderr,
        "3<", \$key,
        "4>", \my $crt,
        "5<", \$pass,
      ;

      $cv->cb( sub {
        &Scalar::Util::weaken( my $R = $R );

        if ( not shift->recv() ) {
          my $w = $R->start_streaming( 200, \@HEADER_JSON );
          $w->write( encode_json( { key => $key, crt => $crt } ) );
          $w->close();
        } else {
          &send_error( $R, &EINT_ERROR(), $stderr );
        }
      } );

    } else {
      &send_error( $R, &BAD_REQUEST() );
    }



  } elsif ( $action eq 'genClientCrt' ) {
    my $serial = $params->{ 'serial' } || '01';
    my $csr = $params->{ 'csr' } || '';
    my $ca_crt = $params->{ 'cacrt' } || '';
    my $ca_key = $params->{ 'cakey' } || '';
    my $ca_pass = $params->{ 'capass' } || '';
    my $days = int( $params->{ 'days' } || 0 );

    my $pw_len = length( $ca_pass );

    if ( $csr ne '' && $ca_crt ne '' && $ca_key ne ''
      && $days > 0 && $pw_len >= $min_pw_len && $pw_len < $max_pw_len )
    {
      my $cv = run_cmd [
        qw( openssl x509 -req -in /dev/fd/3 -CA /dev/fd/4 -CAkey /dev/fd/5 ),
        qw( -out /dev/fd/6 -days ), $days, qw( -set_serial ), $serial,
        qw( -passin fd:7 )
      ],
        "<", "/dev/null",
        ">", \my $stdout,
        "2>", \my $stderr,
        "3<", \$csr,
        "4<", \$ca_crt,
        "5<", \$ca_key,
        "6>", \my $crt,
        "7<", \$ca_pass,
      ;

      $cv->cb( sub {
        &Scalar::Util::weaken( my $R = $R );

        if ( not shift->recv() ) {
          my $w = $R->start_streaming( 200, \@HEADER_JSON );
          $w->write( encode_json( { csr => $csr, crt => $crt } ) );
          $w->close();
        } else {
          &send_error( $R, &EINT_ERROR(), $stderr );
        }
      } );
      
    } else {
      &send_error( $R, &BAD_REQUEST() );
    }

  } elsif ( $action eq 'genP12' ) {
    my $key = $params->{ 'key' } || '';
    my $crt = $params->{ 'crt' } || '';
    my $pwd = $params->{ 'pwd' } || '';
    my $Xpw = $params->{ 'Xpw' } || "\n";

    my $pw_len = length( $pwd );
    
    if ( $key ne '' && $crt ne ''
      && $pw_len >= $min_pw_len && $pw_len < $max_pw_len )
    {
      my $cmd = [
        qw( openssl pkcs12 -export -clcerts ),
        qw( -in /dev/fd/3 -inkey /dev/fd/4 -out /dev/fd/5 ),
        qw( -passin fd:6 -passout fd:7 ),
      ];
      
      my $cv = run_cmd $cmd,
        "<", "/dev/null",
        ">", \my $stdout,
        "2>", \my $stderr,
        "3<", \$crt,
        "4<", \$key,
        "5>", \my $p12,
        "6<", \$pwd,
        "7<", \$Xpw,
      ;

      $cv->cb( sub {
        &Scalar::Util::weaken( my $R = $R );

        if ( not shift->recv() ) {
          my $w = $R->start_streaming( 200, \@HEADER_P12 );
          $w->write( $p12 );
          $w->close();
        } else {
          _500( $R );
        }
      } );

    } else {
      &send_error( $R, &BAD_REQUEST() );
    }
  
  } elsif ( $action eq 'convP12' ) {    
    my $p12 = $params->{ 'p12' } || '';
    my $pwd = $params->{ 'pwd' } || "\n"; # Import Password
    my $ppw = $params->{ 'ppw' } || "\n"; # PEM pass phrase
    
    my $pw_len = length( $pwd );
    
    if ( $p12 ne '' ) {
      my $cv = run_cmd [
        qw( openssl pkcs12 -in /dev/fd/3 -out /dev/fd/4 -clcerts ),
        qw( -passin fd:5 -passout fd:6 )
      ],
        "<", "/dev/null",
        ">", \my $stdout,
        "2>", \my $stderr,
        "3<", \$p12,
        "4>", \my $pem,
        "5<", \$pwd,
        "6<", \$ppw,
      ;
      
      $cv->cb( sub {
        &Scalar::Util::weaken( my $R = $R );

        if ( not shift->recv() ) {
          my $w = $R->start_streaming( 200, \@HEADER_PEM );
          $w->write( $pem );
          $w->close();
        } else {
          _500( $R );
        }

      } );      
      
    } else {
      &send_error( $R, &BAD_REQUEST() );
    }
        
  } else {
    # wrong input
    &send_error( $R, &NOT_IMPLEMENTED() );
  }

  return;
}


=item B<send_error>( $feersum, $error_code, [ $msg ] )

Sends a response with an error code $error_code.

Currently implemented error codes:

=over

=item 0 CONNECTION_ERROR

Connection error on a server side occurs.

=item 1 BAD_REQUEST

Bad request from a client.

=item 2 NOT_IMPLEMENTED

Requested service is not implemented yet.

=item 3 EINT_ERROR

Some sort of an internal error has occurs on a server side.

=item 4 INVALID_NAME

Invalid name. Usually, name is a key in a database.

=item 5 DUPLICATE_ENTRY

Duplicate entry in a database.

=item 6 ENTRY_NOTFOUND

An entry not found in a database.

=item 7 MISSING_DATABASE

The target database name was not found.

=back

=cut


sub send_error($$;$) {
  my ( $R, $code, $msg ) = @_;

  my %data = ( err => $code );
  $data{ 'msg' } = decode_utf8( $msg ) if ( $msg );

  my $w = $R->start_streaming( 200, \@HEADER_JSON );
  $w->write( encode_json( \%data ) );
  $w->close();

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


=item B<genpkey>( $feersum, $name, $type, $bits, [ $cipher, $password ] )

Generates a private key, where are $name is a filename,
$type is either RSA or DSA, $bits is one of the next values: 1024, 2048, 4096.
To create an encrypted private key the additional arguments should be
passed: $cipher is one of DES3, AES128, AES192, AES256; $password is 
a passphrase.

=cut


sub genpkey($$$$;$$) {
  my ( $R, $name, $type, $bits, $cipher, $password ) = @_;


  if ( not check_file_name( $name ) ) {
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
      and return &send_error( $R, &EINT_ERROR(), $stderr );

    # find out a database name to store result
    my $maindb = Local::DB::UnQLite->new( '__db__' );
    my $dbname = $maindb->fetch( '_' )
      || return &send_error( $R, &MISSING_DATABASE() );

    # checks if database settings record exists
    $maindb->fetch( $dbname )
      or return &send_error( $R, &MISSING_DATABASE() );

    my $db = Local::DB::UnQLite->new( $dbname );

    # checks if a key already generated for specified $name
    my $pkeyname = 'pkey_' . $name;

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
      : &send_error( $R, &EINT_ERROR() );
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


=item B<create_db>( $feersum, $name, $description )

Adds new database record with the key $name to an 
internal database '__db__'.

=cut


sub create_db($$$) {
  my ( $R, $name, $desc ) = @_;


  if ( not check_db_name( $name ) ) {
    &send_error( $R, &INVALID_NAME() );
    return;
  }

  my $dbs = Local::DB::UnQLite->new( '__db__' );

  if ( not $dbs->fetch( $name ) ) {
    my %data = ( name => $name, desc => $desc );
    $dbs->store( $name, encode_json( \%data ) )
      ? &send_response( $R, 'name', $name )
      : &send_error( $R, &EINT_ERROR() );
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


  if ( not check_db_name( $name ) ) {
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
      : &send_error( $R, &EINT_ERROR() );
  } else {
    &send_error( $R, &ENTRY_NOTFOUND() );
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


  if ( not check_db_name( $name ) ) {
    &send_error( $R, &INVALID_NAME() );
    return;
  }

  my $dbs = Local::DB::UnQLite->new( '__db__' );

  if ( my $data = $dbs->fetch_json( $name ) ) {
    $data->{ 'desc' } = $desc;
    $dbs->store( $name, encode_json( $data ) )
      ? &send_response( $R, 'name', $name )
      : &send_error( $R, &EINT_ERROR() );
  } else {
    &send_error( $R, &ENTRY_NOTFOUND() );
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


  if ( not check_db_name( $name ) ) {
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
      : &send_error( $R, &EINT_ERROR() );
  } else {
    &send_error( $R, &ENTRY_NOTFOUND() );
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
    &send_error( $R, &ENTRY_NOTFOUND() );
    return;
  }

  return;  
}


=item B<list_dbs>( $feersum )

Sends a response to client side with list of databases.

=cut


sub list_dbs($) {
  my ( $R ) = @_;


  my $dbs = Local::DB::UnQLite->new( '__db__' );
  my $all = $dbs->all_json_except( '_' );

  &send_response( $R, 'dbs', $all );

  return;
}


=item B<remove_all_dbs>( $feersum )

Removes all entries from an internal database '__db__'.

=cut


sub remove_all_dbs($) {
  my ( $R ) = @_;


  my $dbs = Local::DB::UnQLite->new( '__db__' );
  my @keys = $dbs->keys();
  my $num = $dbs->delete_all();

  &Local::DB::UnQLite::closealldb();
  &Local::DB::UnQLite::deletedb( $_ ) for @keys;

  &send_response( $R, 'deleted', $num );
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

Performs a test if a specified file name $name is
valid.

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


=item B<remove_pkey>( $feersum, $name )

Removes from a database a private key with specified name $name.

=cut


sub remove_pkey($$) {
  my ( $R, $name ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $kv = 'pkey_' . $name;

  $db->fetch( $kv )
    or return &send_error( $R, &ENTRY_NOTFOUND() );

  $db->delete( $kv )
    ? &send_response( $R, 'name', $name )
    : &send_error( $R, &EINT_ERROR() );
}


=item B<list_pkeys>( $feersum )

Sends to a client side a list of private keys.

=cut


sub list_pkeys($) {
  my ( $R ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $items = $db->like_json( '^pkey_' );

  # sanitize key text data
  delete $_->{ 'out' } for ( @$items );

  &send_response( $R, 'keys', $items );
}


=item B<remove_all_pkeys>( $feersum )

Removes all private keys entries from a database.

=cut


sub remove_all_pkeys($) {
  my ( $R ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $num = $db->delete_like( '^pkey_' );

  &send_response( $R, 'deleted', $num );
}


=item B<gencsr>( $feersum, $name, $keyname, $subject, [ $keypass ] )

Generates a new certificate request.

=cut


sub gencsr($$$$;$) {
  my ( $R, $name, $keyname, $subj, $keypass ) = @_;


  if ( not check_file_name( $name ) ) {
    &send_error( $R, &INVALID_NAME() );
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

  push @command, '-subj', $subj;

  if ( $keypass ) {
    if ( &check_password( $keypass ) ) {
      push @command, '-passin fd:5';
    } else {
      &send_error( $R, &BAD_REQUEST() );
      return;
    }
  }

  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $kv = 'pkey_' . $keyname;
  my $entry = $db->fetch_json( $kv )
    or return &send_error( $R, &ENTRY_NOTFOUND() );

  my $keyin = $entry->{ 'out' }
    or return &send_error( $R, &EINT_ERROR(), "missing key out");
  push @fdsetup, "3<", \$keyin;

  my $cv = run_cmd [ @command ], @fdsetup;

  $cv->cb( sub {
    &Scalar::Util::weaken( my $R = $R );

    # check if command executed successfully
    shift->recv()
      and return &send_error( $R, &EINT_ERROR(), $stderr );

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
        keyname => $keyname,
        keypass => $keypass ? 'secret' : '',
        subject => $subj,
        out     => $csrout,
      )
    ;

    $db->store( $csrname, encode_json( \%data ) )
      ? &send_response( $R, 'name', $name )
      : &send_error( $R, &EINT_ERROR() );
  } );

  return;
}


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
    or return &send_error( $R, &ENTRY_NOTFOUND() );

  $db->delete( $kv )
    ? &send_response( $R, 'name', $name )
    : &send_error( $R, &EINT_ERROR() );
}

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

sub remove_crt($$) {
  my ( $R, $name ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $kv = 'crt_' . $name;

  $db->fetch( $kv )
    or return &send_error( $R, &ENTRY_NOTFOUND() );

  $db->delete( $kv )
    ? &send_response( $R, 'name', $name )
    : &send_error( $R, &EINT_ERROR() );
}

sub remove_all_crts($) {
  my ( $R ) = @_;


  my $maindb = Local::DB::UnQLite->new( '__db__' );
  my $dbname = $maindb->fetch( '_' )
    or return &send_error( $R, &MISSING_DATABASE() );

  $maindb->fetch( $dbname )
    or return &send_error( $R, &MISSING_DATABASE() );

  my $db = Local::DB::UnQLite->new( $dbname );
  my $num = $db->delete_like( '^crt_' );

  &send_response( $R, 'deleted', $num );
}


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
    or return &send_error( $R, &ENTRY_NOTFOUND() );

  $db->delete( $kv )
    ? &send_response( $R, 'name', $name )
    : &send_error( $R, &EINT_ERROR() );
}

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


=back

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

2015, gh0stwizard

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system itself.

=cut

\&app;
