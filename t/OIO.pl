#!/usr/bin/perl -w

#BEGIN { unshift @INC, '../src/modules'; }

use lib 'src/modules';
use Data::Dumper;
use Local::Templates::OpenSSL::Revoke;

my $t = new Local::Templates::OpenSSL::Revoke
  'CRTS' => [ qw( crt1 crt2 crt3 ) ],
;

#my $dump = $t->dump();
#print Dumper $dump;

#my %args = $t->template_args();
#print Dumper \%args;

if ( my $file = $t->generate() ) {
  print $file, "\n";
  print `cat $file`;
} else {
  die $t->error(), "\n";
}
