package Local::Run;

use strict;
use common::sense;
use AnyEvent;
use AnyEvent::Fork::RPC;
use AnyEvent::Fork;
use AnyEvent::Fork::Pool;
use Local::Server::Settings;
use Local::OpenSSL::Command;
use Data::Dumper;

require Exporter;
our @ISA = qw (Exporter);
our $VERSION = '0.02'; $VERSION = eval "$VERSION";


sub generate_private_key {
    my ( $params, $cb ) = @_;


    my $pwd = $params->{ 'passwd' };
    my $cmd = new Local::OpenSSL::Command
      'command' => 'genrsa',
      'type'    => $params->{ 'type' },
      'bits'    => $params->{ 'bits' },
      'cipher'  => $params->{ 'cipher' },
      'params'  => {
        ':stdout' => \my $stdout,
        ':stderr' => \my $stderr,
        ':keyout' => \my $keyout,
        ':passwd' => \$pwd,
      },
    ;

    $cmd->run->cb (sub {
        my ( $rv ) = shift->recv ();
        AE::log debug => "%s\nreturn: %s", $cmd->dump (), $rv;
        $cmd->destroy ();
        my $data = Local::Data::JSON->new ('err' => 2);
        AE::log debug => Dumper ($data);
        $cb->( $data );
    });

    return;
}

sub genkey {
    goto &generate_private_key;
}


{
  my $pool; # AnyEvent::Fork::Pool object reference
  my %queue;
my $PREFORK;

  sub create_pool() {
    my $setup = Local::Server::Settings->new ();
  
    my $max_proc = $setup->get ('MAXPROC');
    my $max_load = $setup->get ('MAXLOAD');
    my $max_idle = $setup->get ('MAXIDLE') || ( int ($max_proc / 2) || 1 );
    my $start_delay = 0.5;
    my $idle_period = 600;

    my $max_proc_recommended = scalar AnyEvent::Fork::Pool::ncpu ($max_proc);

    if ( $max_proc > $max_proc_recommended ) {
      AE::log info => "max proc. for your system is %d, current is %d",
        $max_proc_recommended,
        $max_proc
      ;
    }
  
    $pool = $PREFORK->require( "Local::Run" )->AnyEvent::Fork::Pool::run
      (
        "Local::Run::execute_logged_safe",
        async => 0, # this type of function does not working async.
        max   => $max_proc,
        idle  => $max_idle,
        load  => $max_load,
        start => $start_delay,
        stop  => $idle_period,
        serializer => $AnyEvent::Fork::RPC::JSON_SERIALISER,
        on_error => \&_pool_error_cb,
        on_event => \&_pool_event_cb,
        on_destroy => \&_pool_destroy_cb,
      )
    ;
    
    return;
  }


=item B<destroy_pool>()

Destroy a pool of worker processes.

=cut


  sub destroy_pool() {
    undef $pool;
  }

  
=item B<run>( command => $cmd, [ %args ], $cb->( $rv ) )

Executes a program $cmd with additinal arguments %args. A callback function
C<<< $cb->() >>> is called with result value $rv: either 1 (ok) or 0 (error).

You may use next arguments for a hash %args:

=over

=item stdout

Sets output file for stdout. If missing redirects output
to I</dev/null>.

=item stderr

Sets error file for stderr. If missing redirects output
to I<stdout>.

=item timeout

Sets a number of seconds before command will be killed
automatically. Default is 10 seconds.

=item euid

Sets an effective uid before executing a command. If missing
using a default value from program settings. See B<drop_privileges>
function below for details.

If the program is running without I<superuser> privileges does
nothing.

=back

=cut

  
  sub run {
    $pool->( @_ );
  }

  sub _pool_error_cb {
    AE::log crit => "pool: @_";
    undef $pool;
  }

  sub _pool_event_cb {
    # using on_event as logger
    AE::log $_[0] => $_[1];
  }
  
  sub _pool_destroy_cb {
    AE::log alert => "pool has been destroyed";
  }

}




scalar "MaryJane - Наше Знамя";


__END__

=pod

=encoding utf-8

=head1 NAME
=head1 SYNOPSIS
=head1 ABSTRACT
=head1 DESCRIPTION
=head2 EXPORT

Nothing by default.

=head2 FUNCTIONS

=over 4

=item B<generate_private_key>, B<genkey>( $params_h, $cb->($DataJSON) )

Generates a private key, where are $name is a filename,
$type is either RSA or DSA, $bits is one of the next values: 1024, 2048, 4096.
To create an encrypted private key the additional arguments should be
passed: $cipher is one of DES3, AES128, AES192, AES256; $password is 
a passphrase.

=cut

=head1 SEE ALSO
=head1 AUTHOR
=head1 COPYRIGHT AND LICENSE

=cut
