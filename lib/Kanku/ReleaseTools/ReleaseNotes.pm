package Kanku::ReleaseTools::ReleaseNotes;

use Moose;
use YAML::PP;
use Data::Dumper;


has 'outfile' => (
  is  => 'rw',
  isa => 'Str',
  lazy=>1,
  builder => '_build_outfile',
);

sub _build_outfile { 
  return 'RELEASE-NOTES-'.$_[0]->release.'.md'
}

with 'Kanku::ReleaseTools::Role';

has '+release' => (required => 1);

sub create {
  my ($self) = @_;
  my $rnotes = $self->blog_releases;
  my $branch = $self->cfg->conf->{blog}->{source_branch};
  die "No blog post found for release ".$self->release unless $rnotes->{$self->release};
  my $infi   = $self->cfg->conf->{blog}->{blogdir}.'/'.$rnotes->{$self->release};
  $infi =~ s#/+#/#g;
  my @yml = $self->git(0, 1, 'show', "$branch:$infi");
  print Dumper(\@yml);
  my $yaml = YAML::PP::Load(join "\n", @yml);

  my $data          = $yaml->{data};
  my $header        = {
    warnings => '',
    features => 'FEATURES',
    fixes    => 'BUGFIXES',
    examples => '',
  };

  my $content = {
    warnings => $data->{warnings} || q{},
    examples => $data->{examples} || q{},
  };

  for my $section ('features', 'fixes') {
    $content->{$section} = q{};
    for my $entry (@{$data->{$section}||[]}) {
      $content->{$section} .= $self->gen_entries($entry, 0);
    }
  }

  for my $section ('warnings','features', 'fixes', 'examples') {
    if ($content->{$section}) {
      my $headline = ($header->{$section}) ? "## $header->{$section}\n" : q{};
      ##########################################################################
      $content->{$section} = <<EOF;
$headline
$content->{$section}

EOF
      ##########################################################################

    }
  }

  open(my $F, '>', $self->outpath)
    || die 'Could not open '.$self->outpath.": $!\n";

  ##############################################################################
  print $F <<EOF;
# $yaml->{title}

$content->{warnings}$content->{features}$content->{fixes}$content->{examples}
EOF
  ##############################################################################

  close $F
    || die 'Could not close '.$self->outpath.": $!\n";

  return $self->outfile;
}

__PACKAGE__->meta->make_immutable;

1;
