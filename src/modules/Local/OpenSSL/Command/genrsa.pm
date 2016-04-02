package Local::OpenSSL::Command::genrsa;

use strict;
use common::sense;
use AnyEvent;

require Exporter;
our @ISA = qw (Exporter);
our $VERSION = '0.01'; $VERSION = eval "$VERSION";

sub show {
    my ( $self ) = @_;

    AE::log debug => "show must go on";

    return 'ehhe';
}

scalar "IAM - L'Ecole Du Micro D'Argent";
