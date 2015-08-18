#!/usr/bin/perl

# 2015, Vitaliy V. Tokarev aka gh0stwizard vitaliy.tokarev@gmail.com
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as the Perl 5 programming language system itself.


use strict;
use common::sense;
use vars qw( $PROGRAM_NAME $VERSION );
use POSIX ();
use Cwd ();
use Getopt::Long qw( :config no_ignore_case bundling );
use File::Spec::Functions ();
use File::Path ();


$PROGRAM_NAME = "plcrtd"; $VERSION = '0.08';


my $retval = GetOptions
  (
    \my %options,
    'help|h',             # print help page and exit
    'version',            # print program version and exit
    'debug',              # enables verbose logging
    'verbose',            # enables very verbose logging
    'pidfile|P=s',        # pid file ( optional )
    'home|H=s',           # chdir to home directory before fork
    'background|B',       # run in background
    'logfile|L=s',        # log file ( optional )
    'enable-syslog',      # enable logging via syslog
    'syslog-facility=s',  # syslog facility
    'quiet|q',            # enable silence mode (no log at all)
    'listen|l=s',         # listen on IP:PORT
    'backend|b=s',        # backend: feersum
    'app|a=s',            # application file
    'work-dir|W=s',       # working directory
    'deploy-dir|D=s',     # deploy directory
  )
;

local $\ = "\n";

if ( defined $retval and !$retval ) {
  # unknown option workaround for GetOpt::Long module
  print "Use --help for help";
  exit 1;
} elsif ( exists $options{ 'help' } ) {
  &print_help();
} elsif ( exists $options{ 'version' } ) {
  &print_version();
} else {
  &set_modules_path();
  &run_program();
}

exit 0;


# ---------------------------------------------------------------------


#
# Adds modules path to @INC when needed.
#
sub set_modules_path() {
  if ( $0 ne '-e' ) {
    # Fix for modules. Perl is able now loading program-specific
    # modules from directory where file main.pl is placed w/o "use lib".
    my $basedir = &get_program_basedir();
    my $mod_dir = "modules";
    unshift @INC, &File::Spec::Functions::rel2abs( $mod_dir, $basedir );
  }

  return;
}

#
# main subroutine
#
sub run_program() {
  &set_default_options();
  &set_default_paths();
  &set_abs_paths();
  &set_env();
  &set_logger();
  &check_pidfile();
  &daemonize();
  &xrun();
}

#
# fork the process
#
sub daemonize() {
  exists $options{ 'background' } or return;

  my $rootdir = ( exists $options{ 'home' } )
    ? $options{ 'home' }
    : &File::Spec::Functions::rootdir();
  chdir( $rootdir )            || die "Can't chdir \`$rootdir\': $!";
  # Due a feature of Perl we are not closing standard handlers.
  # Otherwise, Perl will complains and throws warning messages
  # about reopenning 0, 1 and 2 filehandles.
  my $devnull = '/dev/null';
  open( STDIN, "< $devnull" )  || die "Can't read $devnull: $!";
  open( STDOUT, "> $devnull" ) || die "Can't write $devnull: $!";
  defined( my $pid = fork() )  || die "Can't fork: $!";
  exit if ( $pid );
  ( &POSIX::setsid() != -1 )   || die "Can't setsid: $!";
  open( STDERR, ">&STDOUT" )   || die "Can't dup stderr: $!";
}

#
# Starts a rest major part of the program
#
sub xrun() {
  my $rv;
  my $file = $options{ 'backend' };
  
  if ( $rv = do $file ) {
    return;
  }

  # an error was occured

  if ( $@ ) {
    die "Couldn't parse $file:$\$@";
  }

  if ( $! and ! defined $rv ) {
    die "Couldn't do $file: $!";
  }

  if ( ! $rv ) {
    die "Couldn't run $file!";
  }
}

#
# if pidfile exists throw error and exit
#
sub check_pidfile() {
  $options{ 'pidfile' } || return;
  -f $options{ 'pidfile' } || return;
  printf "pidfile %s: file exists\n", $options{ 'pidfile' };
  exit 1;
}

#
# sets relative paths for files and adds extention to file names
#
sub set_default_paths() {
  my $file_ext = 'pl';
  my %relpaths =
    (
      # option      relative path
      'backend'	=> 'backend',
      'app'	    => 'app',
    )
  ;

  if ( $0 eq '-e' ) {
    # staticperl uses relative paths (vfs)
    for my $option ( keys %relpaths ) {
      my $relpath = $relpaths{ $option };
      my $filename = join '.', $options{ $option }, $file_ext;

      $options{ $option } = &File::Spec::Functions::catfile
        (
          $relpath,
          $filename,
        )
      ;
    }
  } else {
    my $basedir = &get_program_basedir();
    
    for my $option ( keys %relpaths ) {
      my $relpath = $relpaths{ $option };
      my $filename = join '.', $options{ $option }, $file_ext;

      $options{ $option } = &File::Spec::Functions::catfile
        (
          $basedir,
          $relpath,
          $filename,
        )
      ;
    }
  }
  
  return;
}

#
# returns basedir of the program
#
sub get_program_basedir() {
  my $execp = $0;

  if ( $0 eq '-e' ) {
    # staticperl fix
    for ( $^O ) {
      when ( 'linux' ) {
        $execp = &Cwd::abs_path( "/proc/self/exe" );
      }

      when ( 'solaris' ) {
        $execp = &Cwd::abs_path( "/proc/self/path/a.out" );
      }

      default {
        # TODO
        # * freebsd requires a XS module because of missing /proc
        warn "Unable to detect program basedir correctly, using cwd()\n";
        $execp = &Cwd::cwd();
      }
    }
  }

  my ( $vol, $dirs ) = &File::Spec::Functions::splitpath( $execp );

  return &Cwd::abs_path
    (
      &File::Spec::Functions::catpath( $vol, $dirs, "" )
    )
  ;
}

#
# use realpath always
#
sub set_abs_paths() {
  my @pathopts = qw
    (
      logfile
      home
      pidfile
      work-dir
      deploy-dir
    )
  ;

  my $umask = 0750;
  for my $option ( @pathopts ) {
    exists $options{ $option } or next;

    my $path = $options{ $option };
    # naive but simple
    if ( ! &File::Spec::Functions::file_name_is_absolute( $path ) ) {
      my $cwd = &Cwd::cwd();
      $path = &File::Spec::Functions::catdir( $cwd, $path );
      $path = &File::Spec::Functions::rel2abs( $path );
    }
    
    if ( -e $path ) {
      $options{ $option } = &Cwd::abs_path( $path );
    } else {
      # stupid Cwd calls carp() when path does not exists
      # and returns nothing!
      &File::Path::make_path( $path, { mode => $umask } );
      $options{ $option } = &Cwd::abs_path( $path );
    }
  }

  return;
}

sub set_default_options() {
  my %defaultmap =
    (
      'backend'	    => 'feersum',
      'app'	        => 'feersum',
      'work-dir'    => '.',
      'deploy-dir'  => '.',
    )
  ;
  
  for my $option ( keys %defaultmap ) {
    if ( not exists $options{ $option } ) {
      $options{ $option } = $defaultmap{ $option };
    }
  }

  return;
}

#
# use environment variables to exchange between main & child
#
sub set_env() {
  my $prefix = uc( $PROGRAM_NAME );
  my %envmap = 
    (
      #  %options        %ENV
      'pidfile'     => join( '_', $prefix, 'PIDFILE' ),
      'listen'      => join( '_', $prefix, 'LISTEN' ),
      'app'	        => join( '_', $prefix, 'APP_NAME' ),
      'logfile'			=> join( '_', $prefix, 'LOGFILE' ),
      'work-dir'    => join( '_', $prefix, 'WORKDIR' ),
      'deploy-dir'  => join( '_', $prefix, 'DEPLOY_DIR' ),
    )
  ;

  for my $option ( keys %envmap ) {
    if ( exists $options{ $option } ) {
      $ENV{ $envmap{ $option } } //= $options{ $option };
    }
  }
  
  # set basedir
  my $key = join( '_', $prefix, 'BASEDIR' );
  $ENV{ $key } = &get_program_basedir();

  return;
}

#
# We're using AE::Log logger, see 'perldoc AnyEvent::Log' for details.
# Logger is configured via environment variables.
#
sub set_logger() {
  # silence mode
  if ( exists $options{ 'quiet' } ) {
    $ENV{ 'PERL_ANYEVENT_LOG' } = 'log=nolog';
    return;
  }

  my $loglevel = 'filter=note';    # default log level 'notice'
  my $output = 'log=';             # print to stdout by default

  # disables notifications from AnyEvent(?::*) modules
  # they are "buggy" with syslog and annoying
  my $suppress = 'AnyEvent=error';

  if ( exists $options{ 'debug' } ) {
    $loglevel = 'filter=debug';
  }

  if ( exists $options{ 'verbose' } ) {
    $loglevel = 'filter=trace';
  }

  # setup output device: stdout, logfile or syslog

  if ( exists $options{ 'logfile' } ) {
    $output = sprintf( "log=file=%s", $options{ 'logfile' } );
  }

  if ( exists $options{ 'enable-syslog' } ) {
    my $facility = $options{ 'syslog-facility' } || 'LOG_DAEMON';
    $output = sprintf( "log=syslog=%s", $facility );
  }

  if ( exists $options{ 'background' } ) {
    # disables logging when running in background
    # and are not using logfile or syslog
    unless ( exists $options{ 'logfile' }
          || exists $options{ 'enable-syslog' } )
    {
      $ENV{ 'PERL_ANYEVENT_LOG' } = 'log=nolog';
      return;
    }
  }

  $ENV{ 'PERL_ANYEVENT_LOG' } = join
    (
      # A sequence dependence due the "bugs" in AnyEvent and 
      # AnyEvent::Util modules:
      # * Please, no AE::Log() calls into BEGIN {} blocks;
      # * Sys::Syslog::openlog() must be called before
      #   "use AnyEvent(::Util)";
      " ",
      $suppress,
      join( ":", $loglevel, $output ),
    )
  ;

  return;
}

#
# prints help page to stdout
#
sub print_help() {
  print "Allowed options:";

  my $h = "  %-24s %-48s" . $\;

  printf $h, "--help [-h]", "prints this information";
  printf $h, "--version", "prints program version";
  
  print;
  print "Web server options:";

  printf $h, "--listen [-l] arg", "IP:PORT for listener";
  printf $h, "", "- default: \"127.0.0.1:28980\"";  
  printf $h, "--background [-B]", "run process in background (disables logging)";
  printf $h, "", "- default: runs in foreground";
  
  print "Security options:";
  
  printf $h, "--home [-H] arg", "home directory after fork";
  printf $h, "", "- default: root directory";
  printf $h, "--work-dir [-W] arg", "working directory";
  printf $h, "", "- default: .";
  printf $h, "--deploy-dir [-D] arg", "deploy directory";
  printf $h, "", "- default: .";

  print "Logging options:";
  
  printf $h, "--debug", "be verbose";
  printf $h, "--verbose", "be very verbose";
  printf $h, "--quiet [-q]", "disables logging totally";
  printf $h, "--enable-syslog", "enable logging via syslog";
  printf $h, "--syslog-facility arg", "syslog's facility (default is LOG_DAEMON)";
  printf $h, "--logfile [-L] arg", "path to log file (default is stdout)";
  
  print;
  print "Miscellaneous options:";

  printf $h, "--pidfile [-P] arg", "path to pid file (default: none)";
  printf $h, "--backend [-b] arg", "backend name (default: feersum)";
  printf $h, "--app [-a] arg", "application name (default: feersum)";
}

sub print_version() {
  printf "%s version %s%s",
    ( &File::Spec::Functions::splitpath( $PROGRAM_NAME ) )[2],
    $VERSION,
    $\,
  ;
}


__END__

=encoding utf-8

=head1 NAME

plcrtd - Perl OpenSSL Certificate Manager Daemon

=head1 USAGE

plcrtd [-L logfile | --enable-syslog ] [-P pidfile]

=head1 DESCRIPTION

Provides a service to generating OpenSSL certificates.

=head1 OPTIONS

=over

=item --B<help>, -B<h>

Prints help information to I<stdout>.

=item --B<version>

Prints version information to I<stdout>.

=back

=head2 WEB SERVER OPTIONS

=over

=item --B<listen>, -B<l> = I<IP:PORT>

IP address and port number for a web server to listen for.

=item --B<background>, -B<B>

Run the program in the background. By default the program
is running in foreground mode.

If you are enable this option you have to find out useful
--B<logfile>, --B<enable-syslog> options because of
without them the logger is disabled.

=back

=head2 SECURITY OPTIONS

=over

=item --B<home>, -B<H> = I</path/to/home/dir>

Changes home directory when the program is running
in the background mode. Changing the directory approaches
before first fork() call.

=item --B<work-dir>, -B<W> = I</my/work/dir>

Sets a working directory. Inside this directory the program
will keep all its files.

If a specified directory does not exists, it will be
created automatically.

=item --B<deploy-dir>, -B<D> = I</my/deploy/dir>

Sets a deploy directory. Inside this directory the program
will keep deployed certificates and private keys.

=back

=head2 LOGGING OPTIONS

=over

=item --B<debug>

Be verbose.

=item --B<verbose>

Be very verbose.

=item --B<quiet>, -B<q>

Disables logging totally.

=item --B<enable-syslog>

Enables syslog support. Disabled by default.

=item --B<syslog-facility> = I<facility>

Set syslog facility. Default is LOG_DAEMON.

=item --B<logfile>, -B<L> = I</path/to/logfile.log>

A path to log file. When the program is running
in the foreground mode using I<stdout> by default.

=back
  
=head2 MISCELLANEOUS OPTIONS

=over

=item --B<pidfile>, -B<P> = I</path/to/pidfile.pid>

A path to a pid file.

=item --B<backend>, -B<b> = I<backend-name>

A name of a backend file. The program is looking for
the backend file inside of a I<backend/> directory.

You have not to specify an extention of this file.
The program is always using a I<.pl> extention.

Default is 'feersum'.

=item --B<app>, -B<a> = I<application-name>

A name of an application file. The program is looking for
the application file inside of a I<app/> directory.

You have not to specify an extention of this file.
The program is always using a I<.pl> extention.

Default is 'feersum'.

=back

=head1 AUTHOR

Vitaliy V. Tokarev E<lt>vitaliy.tokarev@gmail.comE<gt>

=head1 COPYRIGHT AND DISCLAIMER

2015, gh0stwizard

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system itself.

=cut
