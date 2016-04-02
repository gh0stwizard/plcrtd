package Local::Data::JSON;

use strict;
use common::sense;
use AnyEvent;
use JSON::XS qw (encode_json decode_json);
use Encode ();
use Data::Dumper;

require Exporter;
our @ISA = qw (Exporter);
our $VERSION = '0.01'; $VERSION = eval "$VERSION";


sub new {
    my ( $class, %args ) = @_;


    return bless
      [
        $args{ 'data' },
        $args{ 'err' } // 0,
        $args{ 'msg' },
      ],
      $class
    ;
}

# TODO
# put stuff into a separated module
sub NO_ERROR()          { 0 };
sub BAD_REQUEST()       { 1 };
sub NOT_IMPLEMENTED()   { 2 };
sub INTERNAL_ERROR()    { 3 };
sub INVALID_NAME()      { 4 }; # Invalid entry name
sub DUPLICATE_ENTRY()   { 5 };
sub ENTRY_NOT_FOUND()   { 6 };


sub DATA()      { 0 };
sub ERRNO()     { 1 };
sub MESSAGE()   { 2 };

{
  my %error;
  my %payload;

  sub pop {
    my ( $self ) = @_;


    if ( $error{ 'err' } = $self->[&ERRNO()] ) {
      $error{ 'msg' } = $self->[&MESSAGE()];
      return encode_json (\%error);
    }

    $payload{ 'data' } = $self->[ &DATA() ] || {};
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
