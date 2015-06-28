#!/usr/bin/perl

# This is free software; you can redistribute it and/or modify it
# under the same terms as the Perl 5 programming language system itself.


=encoding utf-8

=head1 NAME

The application for the Feersum.

A modification for the plcrtd project.

=cut


use strict;
use warnings;
use common::sense;
use AnyEvent;
use AnyEvent::Util;
use HTTP::Body ();
use JSON::XS qw( encode_json decode_json );
use Scalar::Util ();
use HTML::Entities ();
use Encode qw( decode_utf8 );
use vars qw( $PROGRAM_NAME );


# body checks
my $MIN_BODY_SIZE = 4;
my $MAX_BODY_SIZE = 524288;

# read buffer size
my $RDBUFFSIZE = 32 * 1024;

# http headers for responses
my @HEADER_JSON = ( 'Content-Type' => 'application/json; charset=UTF-8' );


=head1 FUNCTIONS

=over 4

=cut


sub CONNECTION_ERROR  { 0 } # Connection error
sub BAD_REQUEST       { 1 } # Bad request
sub NOT_IMPLEMENTED   { 2 } # Not implemented
sub EINT_ERROR        { 3 } # Internal error


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
  $body->cleanup( 1 );
  
  my $pos = 0;
  my $chunk = ( $len > $RDBUFFSIZE ) ? $RDBUFFSIZE : $len;

  while ( $pos < $len ) {
    $r->read( my $buf, $chunk ) or last;
    $body->add( $buf );
    $pos += $chunk;
  }

  $r->close();
  
  return $body->param();
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
  
  if ( $action eq 'genCAkey' || $action eq 'genClientKey' ) {
    my $pass = $params->{ 'pass' } || '';
    my $bits = int( $params->{ 'bits' } || 0 );
    
    my $pw_len = length( $pass );

    # Check for a length of $pass was added because of
    # running the command below by a hand does this check.
    #
    # No need to call fork() for obvious result.

    if ( $pw_len >= $min_pw_len && $pw_len < $max_pw_len && $bits >= 1024 ) {
      my $cv = run_cmd [
        qw( openssl genrsa -des3 -passout fd:3 -out /dev/fd/4 ),
        $bits
      ],
        "<", "/dev/null",
        ">", \my $stdout,
        "2>", \my $stderr,
        "3<", \$pass,
        "4>", \my $key,
      ;
      
      $cv->cb( sub {
        &Scalar::Util::weaken( my $R = $R );
      
        if ( not shift->recv() ) {
          my $w = $R->start_streaming( 200, \@HEADER_JSON );
          $w->write( encode_json( { key => $key } ) );
          $w->close();
        } else {
          AE::log error => "genCAkey:\n$stderr";
          &send_error( $R, &EINT_ERROR(), $stderr );
        }        
      } );

    } else {
      &send_error( $R, &BAD_REQUEST() );
    }

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

  } elsif ( $action eq 'genClientCsr' ) {
    my $pass = $params->{ 'pass' } || '';
    my $subj = $params->{ 'subj' } || '';
    my $key = $params->{ 'key' } || '';

    my $pw_len = length( $pass );

    if ( $key ne '' && $subj ne ''
      && $pw_len >= $min_pw_len && $pw_len < $max_pw_len )
    {
      my $cv = run_cmd [
        qw( openssl req -batch -new -key /dev/fd/3 -out /dev/fd/4 ),
        qw( -passin fd:5 -subj ), $subj
      ],
        "<", "/dev/null",
        ">", \my $stdout,
        "2>", \my $stderr,
        "3<", \$key,
        "4>", \my $csr,
        "5<", \$pass,
      ;
      
      $cv->cb( sub {
        &Scalar::Util::weaken( my $R = $R );
      
        if ( not shift->recv() ) {
          my $w = $R->start_streaming( 200, \@HEADER_JSON );
          $w->write( encode_json( { key => $key, csr => $csr } ) );
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


=back

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

2015, gh0stwizard

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system itself.

=cut

\&app;
