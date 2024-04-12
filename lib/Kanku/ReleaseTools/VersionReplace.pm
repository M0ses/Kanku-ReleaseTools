package Kanku::ReleaseTools::VersionReplace;

use strict;
use warnings;
use Moose;
use Data::Dumper;
use File::Path qw/make_path/;
use File::Basename;

has 'outfile' => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

with 'Kanku::ReleaseTools::Role';

has _updated_file_content => (
  is  =>'rw',
  isa => 'Str',
);

sub update_version {
  my ($self, $pattern, $repl) = @_;

  $self->printlog("OUTFILE: ".$self->outfile);
  my $cur    = $self->current_file_content;
  $self->printlog("CURRENT_FILE_CONTENT: ".Dumper($cur));
  my $rel    = $self->release;
  my $out;
  my $c=0;

  for (@{$cur}) {
    $self->printlog("L: $_");
    if (m{$pattern}) {
      print "-$_";
      s{$pattern}{$1$rel$2};
      $c++;
      print "+$_";
    }
    $out .= "$_\n";
  }

  die "Too many 'Version:' lines found ($c)\n" if $c > 1;
  die "No Version lines found (pattern: >>>$pattern<<<)\n" if $c < 1;

  return $self->_updated_file_content($out);
}

sub write_file_for_stashing {
  my ($self) = @_;
  my $out = $self->outpath;
  open(my $fh, '>', $out) || die "Could not open $out: $!";
  print $fh $self->_updated_file_content || die "Could not write to $out: $!";
  close $fh || die "Could not close $out: $!";
  return $self->outfile;
}

__PACKAGE__->meta->make_immutable;

1;
