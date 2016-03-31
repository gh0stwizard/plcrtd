package Local::Data::JSON;

use strict;
use common::sense;
use AnyEvent;
use JSON::XS qw (encode_json decode_json);
use Encode ();
use Data::Dumper;


sub new {
    my ( $class, %args ) = @_;

    return bless
      [
        $args{ 'data' },
        $args{ 'rows' },
        $args{ 'errmsg' },
      ],
      $class
    ;
}


sub NO_ERROR()          { 0 };
sub BAD_REQUEST()       { 1 };
sub NOT_IMPLEMENTED()   { 2 };
sub INTERNAL_ERROR()    { 3 };
sub INVALID_NAME()      { 4 }; # Invalid entry name
sub DUPLICATE_ENTRY()   { 5 };
sub ENTRY_NOT_FOUND()   { 6 };


{
  my %error = ( 'errno' => &INTERNAL_ERROR() );
  my %payload = ( 'data' => undef );

  sub pop {
    if ( $_[0]->[1] < 0 ) {
      return encode_json (\%error);
    }

    $payload{ 'data' } = $_[0]->[0] || {};
    AE::log debug => Dumper (\%payload);
    return encode_json (\%payload);
  }
}


scalar "Platoon";


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
