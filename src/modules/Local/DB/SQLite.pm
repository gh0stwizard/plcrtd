package Local::DB::SQLite;

use strict;
use common::sense;
use AnyEvent;
use DBI;
use DBD::SQLite;
use File::Spec::Functions qw (catfile canonpath);

require Exporter;
our @ISA = qw (Exporter);
our $VERSION = '0.01'; $VERSION = eval "$VERSION";


my $DBFILE = 'plcrtd.db';
my $DBMODE = 'rwc';
my %DBOPTS = 
  (
    'sqlite_unicode'    => 1,
    'RaiseError'        => 1,
    'PrintWarn'         => 0,
    'PrintError'        => 0,
    'AutoCommit'        => 1,
  )
;

{
  my $DB_HOME = '.';

  sub get_db_home() {
    return canonpath ($DB_HOME);
  }

  sub set_db_home($) {
    $DB_HOME = "$_[0]" if ($_[0]);
    return $DB_HOME;
  }
}

{
  my $DBH;

  sub db_open() {
    my $uri = sprintf "dbi:SQLite:uri=file:%s?mode=%s",
        catfile (&get_db_home (), $DBFILE),
        $DBMODE,
    ;
    
    AE::log trace => "connecting to: `%s'", $uri;

    $DBH ||= DBI->connect ($uri, "", "", \%DBOPTS);
    return defined $DBH;
  }

  sub db_close() {
    $DBH || return;
    $DBH->disconnect ();
    undef $DBH;
    return 1;
  }


  my @SCHEMA_QUERIES =
    (
      q{CREATE TABLE IF NOT EXISTS private_keys 
        (
          id            integer primary key,
          type_id       integer,
          key_size      integer default 2048,
          cypher_id     integer,
          password      text,
          key           text not null,
          name          text not null,
          description   text
        )},
      q{CREATE TABLE IF NOT EXISTS requests
        (
          id            integer primary key,
          key_id        integer,
          digest_id     integer,
          subject       text,
          password      text,
          csr           text not null,
          name          text not null,
          description   text
        )},
      q{CREATE TABLE IF NOT EXISTS certificates
        (
          id            integer primary key,
          days          integer,
          serial        integer,
          digest_id     integer,
          key_id        integer,
          cacrt_id      integer,
          cakey_id      integer,
          subject       text,
          password      text,
          crt           text not null,
          name          text not null,
          description   text
        )},
      q{CREATE TABLE IF NOT EXISTS revocations
        (
          id              integer primary key,
          cacrt_id        integer,
          cakey_id        integer,
          name            text not null,
          description     text
        )},
      q{CREATE TABLE IF NOT EXISTS key_types
        (
          id                integer primary key,
          name              text not null
        )},
      q{CREATE TABLE IF NOT EXISTS cypher_types
        (
          id                integer primary key,
          name              text not null
        )}
    )
  ;
  
  my @INDEXES_QUERIES =
    (
      # TODO
    )
  ;

  sub db_check() {
    $DBH || return;

    for my $q ( @SCHEMA_QUERIES, @INDEXES_QUERIES ) {
      AE::log trace => "%s\n%s",
        $q,
        $DBH->do ($q) ? "PASS" : "FAIL",
      ;
    }

    return 1;
  }

  sub get_handle {
      return $DBH;
  }
}


scalar "Каста - Мы берём это на улицах";


__END__

=pod

=encoding utf-8

=head1 NAME

Local::DB::SQLite - SQLite backend module for plcrtd

=head1 SYNOPSIS
=head1 ABSTRACT
=head1 DESCRIPTION
=head2 EXPORT
=head1 SEE ALSO
=head1 AUTHOR
=head1 COPYRIGHT AND LICENSE

=cut

