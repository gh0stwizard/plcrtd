#!/usr/bin/perl

# (c) 2015-2016, Vitaliy V. Tokarev aka gh0stwizard
#
# This is free software; you can redistribute it and/or modify it
# under the same terms as the Perl 5 programming language system itself.


use strict;
use common::sense;
use vars qw( $PROGRAM_NAME $VERSION );
use POSIX ();
use Cwd qw( cwd abs_path );
use Getopt::Long qw( :config no_ignore_case bundling );
use File::Spec::Functions qw( rel2abs catfile catpath splitpath );
use File::Path ();


$PROGRAM_NAME = "plcrtd"; $VERSION = '0.09';


my $STATICPERL = $0 eq '-e'; # staticperl check
my $MODULESDIR = "modules";
my $PR_BASEDIR = &get_program_basedir();

my $retval = GetOptions
  (
    \my %options,
    'help|h|?',           # print help page and exit
    'version|V',          # print program version and exit
    'debug|d',            # enables verbose logging
    'verbose|v',          # enables very verbose logging
    'pidfile|P=s',        # pid file <optional>
    'home|H=s',           # chdir to home directory before fork()
    'background|B',       # run in background
    'logfile|L=s',        # log file <optional>
    'enable-syslog',      # enable logging via syslog
    'syslog-facility=s',  # syslog facility
    'quiet|q',            # enable silence mode (no log at all)
    'listen|l=s',         # listen on IP:PORT
    'backend|b=s',        # backend file: feersum
    'app|a=s',            # application file: feersum
    'work-dir|W=s',       # working directory
    'deploy-dir|D=s',     # deploy directory
  )
;

local $\ = "\n";

if ( defined ($retval) and ! $retval ) {
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
# set_modules_path: adds modules path to @INC when needed.
#
sub set_modules_path() {
  if ( ! $STATICPERL ) {
    # instead of "use lib" ...
    unshift @INC, rel2abs ($MODULESDIR, $PR_BASEDIR);
  }

  return;
}

#
# run_program: perform all neccessary steps to run main 
#
sub run_program() {
  &set_default_options();
  &set_default_paths();
  &set_abs_paths();         # resolve absolute paths to values
  &set_env();               # setup environment vars
  &set_logger();
  &check_pidfile();
  &daemonize();
  &run_script();            # run target script
}

#
# daemonize: fork the process
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
# run_script: starts a rest major part of the program
#
sub run_script() {
  my $rv;
  my $file = $options{ 'backend' };
  
  if ( $rv = do ($file) ) {
    return;
  }

  # an error was occured

  if ( $@ ) {
    die "Couldn't parse $file:$\$@";
  }

  if ( $! and ! defined ($rv) ) {
    die "Couldn't do $file: $!";
  }

  if ( ! $rv ) {
    die "Couldn't run $file!";
  }
}

#
# check_pidfile: if a pidfile exists throw an error and exit
#
sub check_pidfile() {
  $options{ 'pidfile' }     || return;
  -f $options{ 'pidfile' }  || return;
  printf "pidfile %s: file exists\n", $options{ 'pidfile' };
  exit 1;
}

#
# set_default_paths: setup relative paths for files and adds 
# an extention to the their file names
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

  if ( $STATICPERL ) {
    # staticperl uses relative paths (vfs)
    for my $option ( keys %relpaths ) {
      my $relpath = $relpaths{ $option };
      my $filename = join '.', $options{ $option }, $file_ext;

      $options{ $option } = catfile ($relpath, $filename, );
    }
  } else {
    for my $option ( keys %relpaths ) {
      my $relpath = $relpaths{ $option };
      my $filename = join '.', $options{ $option }, $file_ext;

      $options{ $option } = catfile ($PR_BASEDIR, $relpath, $filename, );
    }
  }
  
  return;
}

#
# get_program_basedir: returns basedir of the program
#
sub get_program_basedir() {
  my $execp = $0;

  if ( $STATICPERL ) {
    $execp = $^X;
  }

  for ( $^O ) {
    when ( 'openbsd' ) {
      # XXX
      warn "Unable to detect the program base directory correctly!";
      $execp = cwd ();
    }
  }

  my ( $vol, $dirs ) = splitpath ($execp);
  return abs_path (catpath ($vol, $dirs, ""));
}

#
# set_abs_paths: resolves absolute paths for the option values
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
      $path = &File::Spec::Functions::catdir( cwd (), $path );
      $path = rel2abs ( $path );
    }
    
    if ( ! -e $path ) {
      # stupid Cwd::abs_path() calls carp() when the path is not exists
      # and returns nothing
      &File::Path::make_path( $path, { mode => $umask } );
    }

    $options{ $option } = abs_path ($path);
  }

  return;
}

#
# set_default_options: setup default values for specified options
#
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
# set_env: use environment variables to exchange between main & child
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
  $ENV{ join ('_', $prefix, 'BASEDIR') } = $PR_BASEDIR;

  return;
}

#
# set_logger: AE::Log logger setup; see 'perldoc AnyEvent::Log' for details.
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
    # disables logging when running in the background mode
    # and are not using a logfile or the syslog
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
      join (":", $loglevel, $output),
    )
  ;

  return;
}

#
# print_help: prints help page to stdout
#
sub print_help() {
  print "Allowed options:";

  my $h = "  %-24s %-48s" . $\;

  printf $h, "--help [-h|-?]", "prints this information";
  printf $h, "--version [-V]", "prints program version";
  
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
  
  printf $h, "--debug [-d]", "be verbose";
  printf $h, "--verbose [-v]", "be very verbose";
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

#
# print_version: prints a version of the program
#
sub print_version() {
  printf "%s version %s%s",
    ( splitpath ($PROGRAM_NAME) )[2],
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

Provides a web service to managing of OpenSSL certificates.

=head1 OPTIONS

=over

=item --B<help>, -B<h>, -B<?>

Prints help information to I<stdout>.

=item --B<version>, -B<V>

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

=item --B<debug>, -B<d>

Be verbose.

=item --B<verbose>, -B<v>

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

(c) 2015-2016, Vitaliy V. Tokarev

This is free software; you can redistribute it and/or modify it
under the same terms as the Perl 5 programming language system itself.

=cut
