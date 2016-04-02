package Local::OpenSSL::Command;

use strict;
use common::sense;
use AnyEvent;

require Exporter;
our @ISA = qw (Exporter);
our $VERSION = '0.01'; $VERSION = eval "$VERSION";


sub new {
    my ( $class, %args ) = @_;


    return bless { 'command' => 'undefined', %args }, $class;
}

sub run {
    my ( $self ) = @_;


    my $cv = AE::cv;
    my $t; $t = AE::timer 1, 0, sub {
        undef $t;
        $cv->send(42);
    };
    return $cv;
}

sub dump {
    my ( $self ) = @_;


  #'openssl genrsa -out /a/b/key -aes256 -passout fd:X BITS';

    return '<todo>';
}

sub DESTROY {
  
}

sub destroy {
    my ( $self ) = @_;


    $self->DESTROY();
    %$self = ();
    bless $self, 'Local::OpenSSL::Command::destroyed';
}

sub destroyed { 0 }
sub Local::OpenSSL::Command::destroyed::destroyed   { 1 }
sub Local::OpenSSL::Command::destroyed::AUTOLOAD    {   }


scalar "Beseech - Gimme Gimme Gimme";


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

