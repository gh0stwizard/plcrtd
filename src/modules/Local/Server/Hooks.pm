package Local::Server::Hooks;

use strict;
require Exporter;
our @ISA = qw (Exporter);
our $VERSION = '0.01'; $VERSION = eval "$VERSION";

use Local::DB::UnQLite;
use Local::Server::Settings;

sub new {
    bless {}, shift;
}

sub on_start {
    my $setup = Local::Server::Settings->new();
    &Local::DB::UnQLite::set_db_home ($setup->get ('WORKDIR'));
}

sub on_before_start {
    goto &on_start;
}

sub on_after_start {

}

sub on_reload {
    &Local::DB::UnQLite::closealldb();
}

sub on_shutdown {
    &Local::DB::UnQLite::closealldb();
}


scalar "Imphenzia - Cybex";


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
