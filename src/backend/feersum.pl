#!/usr/bin/perl

=pod

=encoding utf-8

=head1 NAME

The HTTP server written in Perl, powered by Feersum: B<plcrtd> project.

=cut


# Workaround for AnyEvent::Fork->new() + staticperl:
#  Instead of using a Proc::FastSpawn::spawn() call
#  just fork the current process.
#
# Creates a parent, template process; setup a value of $TEMPLATE
use AnyEvent::Fork::Early;
# new() method uses the $TEMPLATE variable;
# see AnyEvent/Fork.pm "sub new" for details.
my $PREFORK = AnyEvent::Fork->new();


# the main (http server) program begins here
use strict;
use common::sense;
use vars qw| $PROGRAM_NAME $VERSION |;
use EV;
use Feersum;
use AnyEvent;
use AnyEvent::Socket;
use AnyEvent::Handle;
use AnyEvent::Util qw| run_cmd |;
use Socket ();
use Local::Server::Settings;
use Local::Server::Hooks;


# initialize the server configuration
my $SETUP = Local::Server::Settings->new ($PROGRAM_NAME);
# hooks may depends on the server configuration...
my $HOOKS = Local::Server::Hooks->new ($PREFORK);


{
  # program entrypoint: start the server asynchronously
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


=head1 DESCRIPTION

TBA

=head2 FUNCTIONS

=over 4

=item B<start_server>()

Start the server process.

=cut


sub start_server() {
  &enable_syslog();
  &debug_settings();
  &write_pidfile();

  $HOOKS->on_before_start();
  &start_httpd();
  $HOOKS->on_after_start();

  AE::log note => "%s/%s Listen on %s:%d, PID = %d",
    $PROGRAM_NAME,
    $VERSION,
    parse_listen(),
    $$,
  ;
}


=item B<shutdown_server>()

Shutdown the server process.

=cut


sub shutdown_server() {
  &unlink_pidfile();
  &stop_httpd();

  $HOOKS->on_shutdown ();
  &EV::unloop();
}


=item B<reload_server>()

Reload a server process.

=cut


sub reload_server() {
  &reload_syslog();  
  &stop_httpd();

  $HOOKS->on_reload ();
  &start_httpd();

  AE::log note => "Server restarted, PID = %d", $$;
}


=item B<enable_syslog>()

Enables syslog.

=cut


sub enable_syslog() {
  my $facility = &get_syslog_facility() || return;

  require Sys::Syslog;
  # open log with options: nodelay, include pid
  &Sys::Syslog::openlog ($PROGRAM_NAME, 'ndelay,pid', $facility);
}


=item B<reload_syslog>()

Reload syslog context.

=cut


sub reload_syslog() {
  my $facility = &get_syslog_facility() || return;

  require Sys::Syslog;
  &Sys::Syslog::closelog ();
  &Sys::Syslog::openlog ($PROGRAM_NAME, 'ndelay,pid', $facility);
}


=item $facility = B<get_syslog_facility>()

Returns a syslog facility name from C< $ENV{ PERL_ANYEVENT_LOG } >
variable.

=cut


sub get_syslog_facility() {
  $ENV{ 'PERL_ANYEVENT_LOG' } =~ m/syslog=([_\w]+)$/ or return;
  return "$1";
}


{
  my $Instance;
  my $socket;


=item B<start_httpd>()

Starts Feersum server.

=cut


  sub start_httpd() {
    $Instance ||= Feersum->endjinn ();

    my ( $addr, $port ) = &parse_listen ();
    $socket = &create_socket ($addr, $port);

    if ( my $fd = fileno ($socket) ) {
      $Instance->accept_on_fd ($fd);
      $Instance->set_server_name_and_port ($addr, $port);
      $Instance->request_handler (&load_app ());
      return;
    }

    AE::log fatal => "Could not retrieve fileno %s:%d: %s",
      $addr, $port, $!;
  }


=item B<stop_httpd>()

Stops Feersum server.

=cut


  sub stop_httpd() {
    ref $Instance eq 'Feersum' or return;

    $Instance->request_handler (\&_503); # for new requests
    $Instance->unlisten();
    close ($socket)
      or AE::log error => "Close listen socket: %s", $!;
    undef $socket;
    undef $Instance;
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

  my $proto = &AnyEvent::Socket::getprotobyname ('tcp');

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

  &AnyEvent::Util::fh_nonblocking ($socket, 1);

  my $sa = &AnyEvent::Socket::pack_sockaddr
  (
    $port,
    &AnyEvent::Socket::aton ($addr),
  );

  bind ($socket, $sa) or do {
    AE::log fatal => "Could not bind %s:%d: %s",
      $addr,
      $port,
      $!,
    ;
  };

  listen ($socket, $SETUP->get ('SOMAXCONN')) or do {
    AE::log fatal => "Could not listen %s:%d: %s",
      $addr,
      $port,
      $!,
    ;
  };

  return $socket;
}


=item ( $addr, $port ) = B<parse_listen>()

Returns IP address $addr and port $port to listen using a configuration
information (currently, through environment variables).
See L<Local::Server::Settings> for details.

=cut


sub parse_listen() {
  my ( $cur_addr, $cur_port ) = split ':', $SETUP->get ('LISTEN');
  my ( $def_addr, $def_port ) = split ':', $SETUP->get_default ('LISTEN');

  $cur_addr ||= $def_addr;
  $cur_port ||= $def_port;

  return( $cur_addr, $cur_port );
}


=item $app = B<load_app>()

Try to load an application for Feersum. Returns a
reference to subroutine application. If the application unable
to load returns a predefined subroutine with 500 HTTP code.

The application supposed to be a casual Perl script, which returns
the CODE reference. See L<Feersum> for details.

=cut


sub load_app() {
  my $file = $SETUP->get ('APP_NAME');
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

Prints the application settings to an output log.

=cut


sub debug_settings() {
  for ( sort $SETUP->list () ) {
    AE::log debug => "%s = %s", $_, $SETUP->get ($_);
  }
}


=item B<write_pidfile>()

Creates a pidfile. If an error occurs stops the program.

=cut


sub write_pidfile() {
  my $file = $SETUP->get ('PIDFILE') || return;

  open (my $fh, ">", $file)
    or AE::log fatal => "open pidfile %s: %s", $file, $!;
  syswrite ($fh, $$)
    or AE::log fatal => "write pidfile %s: %s", $file, $!;
  close ($fh)
    or AE::log fatal => "close pidfile %s: %s", $file, $!;
}


=item B<unlink_pidfile>()

Removes a pidfile from a disk. Returns a status code of the
B<unlink>() function.

=cut


sub unlink_pidfile() {
  my $file = $SETUP->get ('PIDFILE') || return;
  unlink ($file)
    or AE::log error => "unlink pidfile %s: %s", $file, $!;
}

=back

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

(c) 2015-2016, Vitaliy V. Tokarev

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system itself.

=cut

EV::run; scalar "Within Temptation - Towards The End";
