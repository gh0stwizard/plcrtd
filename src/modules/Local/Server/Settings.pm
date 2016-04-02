package Local::Server::Settings;

use strict;
require Exporter;
our @ISA = qw (Exporter);
our $VERSION = '0.02'; $VERSION = eval "$VERSION";

use Socket ();
use Env;

my %DEFAULT_SETTINGS =
  (
    'LISTEN'      => '127.0.0.1:28980',
    'APP_NAME'    => 'app+feersum.pl',
    'SOMAXCONN'   => &Socket::SOMAXCONN(),
    'PIDFILE'     => '',
    'LOGFILE'     => '',
    'WORKDIR'     => '.',
    'DEPLOY_DIR'  => '.',
    'MAXPROC'     => 4, # max. number of forked processes
    'MAXLOAD'     => 1, # max. number of queued queries per worker process
    'MAXIDLE'     => 4, # max. number of idle workers
  )
;

{
    my $INSTANCE;
    my $KEY;

    sub new {
        my ( $class, $key ) = @_;
    
        return $INSTANCE if $INSTANCE;

        $INSTANCE = bless {}, $class;
        $KEY = uc "$key";
        $INSTANCE->update();
    }

    sub update {
        my ( $self ) = @_;

        for my $var ( keys %DEFAULT_SETTINGS ) {
            my $envname = join ('_', $KEY, $var);
    
            $self->{ $var } = defined ($ENV{ $envname })
                ? $ENV{ $envname }
                : $DEFAULT_SETTINGS{ $var };
        }
    
        return $self;
    }
}

sub get {
    my ( $self, $name ) = @_;

    if ( exists $self->{ $name } ) {
        return $self->{ $name };
    }

    return;
}

sub get_default {
    my ( $self, $name ) = @_;

    if ( exists $DEFAULT_SETTINGS{ $name } ) {
        return $DEFAULT_SETTINGS{ $name };
    }

    return;
}

sub list {
    return keys %{ $_[0] };
}


scalar "Imphenzia - The Fallen";


__END__

=pod

=encoding utf-8

=head1 NAME
=head1 SYNOPSIS
=head1 ABSTRACT
=head1 DESCRIPTION
=head2 EXPORT
=head1 SEE ALSO
=head1 AUTHOR
=head1 COPYRIGHT AND LICENSE

=cut
