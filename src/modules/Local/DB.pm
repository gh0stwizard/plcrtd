package Local::DB;

use strict;
use common::sense;
use DBI qw (:sql_types);
use Local::DB::SQLite;
use Local::Data::JSON;

require Exporter;
our @ISA = qw (Exporter);
our $VERSION = '0.01'; $VERSION = eval "$VERSION";


# SELECT Queries
sub S_LIST_KEYS()     { 0 };

my @S_QUERIES =
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


# INSERT Queries
sub I_CREATE_KEY()    { 0 };

my @I_QUERIES =
  (
    q{INSERT INTO private_keys
        (name, key, type_id, cypher_id)
      VALUES
        (?, ?, ?, ?)},
  )
;


# UPDATE Queries
#sub U_


sub list_keys {
    my @data;
    my $dbh = &Local::DB::SQLite::get_handle ();
    my $qry = $S_QUERIES[ &S_LIST_KEYS() ];
    my $sth = $dbh->prepare ($qry);
    $sth->execute ();
    my $rows = $sth->rows();
    AE::log debug => "%s\n  rows: %d", $qry, $rows;
    my %row;
    $sth->bind_columns( \( @row{ @{ $sth->{'NAME_lc'} } } ));
    while ($sth->fetch ()) {
      push @data,
        {
          'id'        => $row{ 'id' },
          'name'      => $row{ 'name' },
          'type'      => $row{ 'type' },
          'size'      => $row{ 'size' },
          'cypher'    => $row{ 'cypher' },
          'passwd'    => $row{ 'passwd' },
        }
      ;
    }

    return Local::Data::JSON->new ('data' => \@data);
}


sub create_key($$) {
    my ( $params, $key ) = @_;


    my $name        = $params->{ 'name' };
    my $type        = $params->{ 'type' };
    my $size        = int ($params->{ 'bits' } || 0);
    my $cipher_id   = $params->{ 'cipher' };
    my $passwd      = $params->{ 'passwd' };

    my $dbh = &Local::DB::SQLite::get_handle ();
    my $sth = $dbh->prepare ($I_QUERIES[ &I_CREATE_KEY() ]);

    # (name, key, type_id, cypher_id)
    $sth->bind_param(1, $name, SQL_VARCHAR);
    $sth->bind_param(2, $key, SQL_VARCHAR);
    #$sth->bind_param(3, $type_id, SQL_INTEGER);
    #$sth->bind_param(4, $cypher_id, SQL_INTEGER);

    $sth->execute();
    
    return Local::Data::JSON->new ('errno' => 2);
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
