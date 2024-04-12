package Kanku::ReleaseTools;

use Moose;
use Build::Rpm;
our $VERSION = '0.0.1';


has 'outfile' => (
  is => 'rw',
  isa => 'Str',
  lazy => 1,
  default => 'SOMETHING_WENT_WRONG.txt',
);

with 'Kanku::ReleaseTools::Role';

sub release_not_newer {
  my ($self) = @_;
  return  !(&Build::Rpm::verscmp($self->release, $self->latest_tag) > 0);
}

__PACKAGE__->meta->make_immutable;

1;
