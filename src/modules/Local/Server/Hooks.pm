package Local::Server::Hooks;

use strict;
use common::sense;
use Local::Server::Settings;
use Local::DB::SQLite;

require Exporter;
our @ISA = qw (Exporter);
our $VERSION = '0.02'; $VERSION = eval "$VERSION";


sub new {
    bless {}, shift;
}

sub on_start {
    my $setup = Local::Server::Settings->new();
    &Local::DB::SQLite::set_db_home ($setup->get ('WORKDIR'));
    &Local::DB::SQLite::db_open();
}

sub on_before_start {
    goto &on_start;
}

sub on_after_start {
    &Local::DB::SQLite::db_check();
}

sub on_reload {
    &Local::DB::SQLite::db_close();
}

sub on_shutdown {
    &Local::DB::SQLite::db_close();
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
