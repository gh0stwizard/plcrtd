package Local::DB;

use strict;
use common::sense;
use AnyEvent;
use Local::DB::SQLite;
use Local::Data::JSON;
use Data::Dumper;

require Exporter;
our @ISA = qw (Exporter);
our $VERSION = '0.01'; $VERSION = eval "$VERSION";


my @QUERIES =
  (
    q{SELECT
        pk.id,
        pk.name,
        pk.key_size     AS size,
        types.name      AS type,
        cypher.name     AS cypher,
        pk.password     AS passwd 
      FROM private_keys pk 
      LEFT JOIN (SELECT * FROM key_types) types
        ON (pk.type_id = types.id)
      LEFT JOIN (SELECT * FROM cypher_types) cypher
        ON (pk.cypher_id = cypher.id)},
  )
;

sub LISTKEYS() { 0 };


sub list_keys {
    my @data;
    my $dbh = &Local::DB::SQLite::get_handle ();
    my $sth = $dbh->prepare ($QUERIES[ &LISTKEYS() ]);
    $sth->execute ();
    my %row;
    $sth->bind_columns( \( @row{ @{$sth->{NAME_lc} } } ));
    while ($sth->fetch ()) {
      push @data, {
        'id'        => $row{ 'id' },
        'name'      => $row{ 'name' },
        'type'      => $row{ 'type' },
        'size'      => $row{ 'size' },
        'cypher'    => $row{ 'cypher' },
        'passwd'    => $row{ 'passwd' },
      };
    }

    return new Local::Data::JSON
      'data' => \@data,
      'rows' => $sth->rows(),
    ;
}


scalar "E Nomine - Das Tier In Mir";


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
