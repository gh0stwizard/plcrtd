#!/usr/bin/perl

# 2015, Vitaliy V. Tokarev aka gh0stwizard vitaliy.tokarev@gmail.com
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as the Perl 5 programming language system itself.


=encoding utf-8

=head1 NAME

The HTTP server written in Perl, powered by Feersum.

A modification for the plcrtd project.

=cut


use strict;
use common::sense;
use vars qw( $PROGRAM_NAME $VERSION );
use Feersum;
use EV;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::Util qw( run_cmd );
use Socket ();
use Local::DB::UnQLite;


my %CURRENT_SETTINGS;
my %DEFAULT_SETTINGS =
  (
    'LISTEN'    => '127.0.0.1:28980',
    'APP_NAME'  => 'app+feersum.pl',
    'SOMAXCONN' => &Socket::SOMAXCONN(),
    'PIDFILE'   => '',
    'LOGFILE'   => '',
    'WORKDIR'   => '.',
  )
;


{
  my $t; $t = AE::timer 0, 0, sub {
    undef $t;
    &start_server();
  };

  my %signals; %signals = 
  (
    'HUP' => sub {
      AE::log alert => "SIGHUP recieved, reloading";
      &reload_server();
    },
    'INT' => sub {
      AE::log alert => 'SIGINT recieved, shutdown';
      %signals = ();
      &shutdown_server();
    },
    'TERM' => sub {
      AE::log alert => 'SIGTERM recieved, shutdown';
      %signals = ();
      &shutdown_server();
    },
  );

  %signals = map {
    # signal name         AE::signal( NAME, CALLBACK )
    +"$_"         =>      AE::signal( $_, $signals{ $_ } )
  } keys %signals;

  $EV::DIED = sub {
    AE::log fatal => "$@";
  };

  {
    no strict 'refs';
    *{ 'Feersum::DIED' } = sub {
      AE::log fatal => "@_";
    };
  }
}

# ---------------------------------------------------------------------

=head1 FUNCTIONS

=over 4


=item B<start_server>()

Start a server process.

=cut


sub start_server() {
  &update_settings();
  &enable_syslog();
  &debug_settings();
  &write_pidfile();
  &Local::DB::UnQLite::set_db_home( &get_setting( 'WORKDIR' ) );
  &start_httpd();

  AE::log note => "Listen on %s:%d, PID = %d",
    parse_listen(),
    $$,
  ;
}


=item B<shutdown_server>()

Shutdown a server process.

=cut


sub shutdown_server() {
  &unlink_pidfile();
  &stop_httpd();
  &Local::DB::UnQLite::closealldb();
  &EV::unloop();
}


=item B<reload_server>()

Reload a server process.

=cut


sub reload_server() {
  &reload_syslog();  
  &stop_httpd();
  &Local::DB::UnQLite::closealldb();
  &start_httpd();

  AE::log note => "Server restarted, PID = %d", $$;
}


=item B<update_settings>()

Updates the server settings either by %ENV variables or
default settings.

=cut


sub update_settings() {
  for my $var ( keys %DEFAULT_SETTINGS ) {
    my $envname = join '_', uc( $PROGRAM_NAME ), $var;
    
    $CURRENT_SETTINGS{ $var } = defined( $ENV{ $envname } )
      ? $ENV{ $envname }
      : $DEFAULT_SETTINGS{ $var }
    ;
  }
}


=item B<enable_syslog>()

Enables syslog.

=cut


sub enable_syslog() {
  my $facility = &get_syslog_facility() || return;

  require Sys::Syslog;

  &Sys::Syslog::openlog
    (
      $PROGRAM_NAME,
      'ndelay,pid', # nodelay, include pid
      $facility,
    )
  ;
}


=item B<reload_syslog>()

Reload syslog context.

=cut


sub reload_syslog() {
  my $facility = &get_syslog_facility() || return;

  require Sys::Syslog;

  &Sys::Syslog::closelog();

  &Sys::Syslog::openlog
    (
      $PROGRAM_NAME,
      'ndelay,pid',
      $facility,
    )
  ;
}


=item $facility = B<get_syslog_facility>()

Returns a syslog facility name from C< $ENV{ PERL_ANYEVENT_LOG } >
variable.

=cut


sub get_syslog_facility() {
  $ENV{ 'PERL_ANYEVENT_LOG' } =~ m/syslog=([_\w]+)$/ or return;
  return "$1";
}


=item B<start_httpd>()

Starts Feersum.

=cut

{
  my $Instance;
  my $socket;

  sub start_httpd() {
    $Instance ||= Feersum->endjinn();

    my ( $addr, $port ) = parse_listen();
    $socket = &create_socket( $addr, $port );

    if ( my $fd = fileno( $socket ) ) {
      $Instance->accept_on_fd( $fd );
      $Instance->set_server_name_and_port( $addr, $port );
      $Instance->request_handler( &load_app() );
      return;
    }

    AE::log fatal => "Could not retrieve fileno %s:%d: %s",
      $addr, $port, $!;
  }


=item B<stop_httpd>()

Stops Feersum.

=cut


  sub stop_httpd() {
    ref $Instance eq 'Feersum' or return;

    $Instance->request_handler( \&_503 );
    $Instance->unlisten();
    close( $socket )
      or AE::log error => "Close listen socket: %s", $!;
    undef $socket;
  }
}

sub _405 {
  $_[0]->send_response
  (
    405,
    [ 'Content-Type' => 'text/plain' ],
    [ "Method Not Allowed" ],
  );
}

sub _500 {
  $_[0]->send_response
  (
    500,
    [ 'Content-Type' => 'text/plain' ],
    [ 'Internal Server Error' ],
  );
}

sub _501 {
  $_[0]->send_response
  (
    501,
    [ 'Content-Type' => 'text/plain' ],
    [ 'Not Implemented' ],
  );
}

sub _503 {
  $_[0]->send_response
  (
    503,
    [ 'Content-Type' => 'text/plain' ],
    [ 'Service Unavailable' ],
  );
}


=item $sock = B<create_socket>( $addr, $port )

Creates SOCK_STREAM listener socket with next options:

=over

=item SO_REUSEADDR

=item SO_KEEPALIVE

=back

=cut


sub create_socket($$) {
  my ( $addr, $port ) = @_;

  my $proto = &AnyEvent::Socket::getprotobyname( 'tcp' );

  socket
  (
    my $socket,
    &Socket::PF_INET,
    &Socket::SOCK_STREAM,
    $proto,
  ) or do {
    AE::log fatal => "Could not create socket %s:%d: %s",
      $addr,
      $port,
      $!,
    ;
  };

  setsockopt
  (
    $socket,
    &Socket::SOL_SOCKET(),
    &Socket::SO_REUSEADDR(),
    pack( "l", 1 ),
  ) or AE::log error => "Could not setsockopt SO_REUSEADDR %s:%d: %s",
    $addr,
    $port,
    $!,
  ;

  setsockopt
  (
    $socket,
    &Socket::SOL_SOCKET(),
    &Socket::SO_KEEPALIVE(),
    pack( "I", 1 ),
  ) or AE::log error => "Could not setsockopt SO_KEEPALIVE %s:%d: %s",
    $addr,
    $port,
    $!,
  ;

  &AnyEvent::Util::fh_nonblocking( $socket, 1 );

  my $sa = &AnyEvent::Socket::pack_sockaddr
  (
    $port,
    &AnyEvent::Socket::aton( $addr ),
  );

  bind( $socket, $sa ) or do {
    AE::log fatal => "Could not bind %s:%d: %s",
      $addr,
      $port,
      $!,
    ;
  };

  listen( $socket, &get_setting( 'SOMAXCONN' ) ) or do {
    AE::log fatal => "Could not listen %s:%d: %s",
      $addr,
      $port,
      $!,
    ;
  };

  return $socket;
}


=item ( $addr, $port ) = B<parse_listen>()

Returns IP address $addr and port $port to listen.

=cut


sub parse_listen() {
  my ( $cur_addr, $cur_port ) = split ':', $CURRENT_SETTINGS{ 'LISTEN' };
  my ( $def_addr, $def_port ) = split ':', $DEFAULT_SETTINGS{ 'LISTEN' };

  $cur_addr ||= $def_addr;
  $cur_port ||= $def_port;

  return( $cur_addr, $cur_port );
}


=item $app = B<load_app>()

Try to load an application for Feersum. Returns a
reference to subroutine application. If the application unable
to load returns a predefined subroutine with 500 HTTP code.

=cut


sub load_app() {
  my $file = $CURRENT_SETTINGS{ 'APP_NAME' } || $DEFAULT_SETTINGS{ 'APP_NAME'};
  my $app = do( $file );

  if ( ref $app eq 'CODE' ) {
    return $app;
  }

  if ( $@ ) {
    AE::log error => "Couldn't parse %s: %s", $file, "$@";
  }

  if ( $! && !defined $app ) {
    AE::log error => "Couldn't do %s: %s", $file, $!;
  }

  if ( !$app ) {
    AE::log error => "Couldn't run %s", $file;
  }

  return \&_500;
}


=item B<debug_settings()>

Prints settings to output log.

=cut


sub debug_settings() {
  # print program settings
  AE::log debug => "%s = %s", $_, $CURRENT_SETTINGS{ $_ }
    for ( sort keys %CURRENT_SETTINGS );  
}


=item B<write_pidfile>()

Creates a pidfile. If an error occurs stops the program.

=cut


sub write_pidfile() {
  my $file = &get_setting( 'PIDFILE' ) || return;

  open( my $fh, ">", $file )
    or AE::log fatal => "open pidfile %s: %s", $file, $!;
  syswrite( $fh, $$ )
    or AE::log fatal => "write pidfile %s: %s", $file, $!;
  close( $fh )
    or AE::log fatal => "close pidfile %s: %s", $file, $!;
}


=item B<unlink_pidfile>()

Removes a pidfile from a disk.

=cut


sub unlink_pidfile() {
  my $file = &get_setting( 'PIDFILE' ) || return;
  unlink( $file )
    or AE::log error => "unlink pidfile %s: %s", $file, $!;
}


=item $value = B<get_setting>( $name )

Returns a current settings value by a name $name.

=cut


sub get_setting($) {
  my ( $name ) = @_;


  if ( exists $CURRENT_SETTINGS{ $name } ) {
    return $CURRENT_SETTINGS{ $name };
  } else {
    return;
  }

}


=back

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

2015, gh0stwizard

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system itself.

=cut

EV::run; scalar "Towards The End";
