package Kanku::ReleaseTools::Config;

use Moose;
use Cwd;
use FindBin;
use File::Spec;
use YAML::PP;


has 'basedir' => (
  is      => 'rw',
  isa     => 'Str',
  lazy    => 1,
  builder => '_build_basedir',
);

sub _build_basedir { 
  Cwd::abs_path("$FindBin::Bin/../..");
}

has 'config_file' => (
  is => 'rw',
  isa => 'Str',
  lazy => 1,
  builder => '_build_config_file',
);

sub _build_config_file {
  my ($self) = @_;
  # TODO: path traversal like git/osc
  my $p = Cwd::abs_path($self->basedir."/.krt.yml");
  die "Config file $p does not exist" unless -f $p;
  return $p;
}

has 'conf' => (
  is => 'rw',
  isa => 'HashRef',
  builder => '_build_conf',
);

sub _build_conf {
  my ($self) = @_;
  return YAML::PP::LoadFile($self->config_file);
}

__PACKAGE__->meta->make_immutable;

1;
