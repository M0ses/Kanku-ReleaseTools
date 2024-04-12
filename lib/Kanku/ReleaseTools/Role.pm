package Kanku::ReleaseTools::Role;

use strict;
use warnings;
use Carp;
use FindBin;
use Moose::Role;
use Moose::Util::TypeConstraints;

requires 'outfile';

subtype 'GitTag',
  as 'Str',
  where { /^v?\d+\.\d+\.\d+$/ };

subtype 'ExistantDir',
  as 'Str',
  where { -d $_ };

has 'cfg' => (
  is       => 'ro',
  isa      => 'Object',
  required => 1,
);

has 'release' => (
  is       => 'ro',
  isa      => 'GitTag',
);

has 'destination_branch' => (
  is       => 'ro',
  isa      => 'Str',
  default  => 'master',
);

has 'blog_dir' => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has 'basedir' => (
  is       => 'ro',
  isa      => 'ExistantDir',
  lazy     => 1,
  default  => "$FindBin::Bin/../..",
);

has 'outdir' => (
  is       => 'ro',
  isa      => 'Str',
  required => 1,
);

has 'outpath' => (
  is       => 'ro',
  isa      => 'Str',
  lazy     => 1,
  builder  => '_build_outpath',
);

sub _build_outpath {
  my ($s) = @_;
  my $f = $s->outdir.'/'.$s->outfile;
$s->printlog("OUTPATH: $f");
  $f =~ s#/+#/#g;
  return $f
}
  
has 'dry_run' => (
  is       => 'ro',
  isa      => 'Bool',
  default  => 0,
);

has 'debug' => (
  is       => 'ro',
  isa      => 'Bool',
  default  => sub { $::ENV{KRT_DEBUG} || 0},
);

has 'headers' => (
  is      => 'ro',
  isa     => 'HashRef',
  default => sub {
    return {
      warnings => '',
      features => 'FEATURES',
      fixes    => 'BUGFIXES',
      examples => '',
    };
  },
);

has 'blog_releases' => (
  is      => 'rw',
  isa     => 'HashRef',
  lazy    => 1,
  builder => '_build_blog_releases',
);

sub _build_blog_releases {
    my ($self) = @_;
    my $branch = $self->cfg->conf->{blog}->{source_branch};
    my $dir    = $self->cfg->conf->{blog}->{blogdir};
    $dir =~ s#/+#/#g;
    $dir =~ s#/+$##g;
    my @files  = $self->git(0, 1 , 'ls-tree', '-r', '--name-only', "$branch:$dir");
    my %rnotes;
  
    my $pattern = '.*/release-(.*)/index.md';
    for my $f (@files) {
      if ( $f =~ m#$pattern#) {
	chomp $f;
        $rnotes{$1} = $f;
      }       
    }
    return \%rnotes,
}

sub load_yaml_from_branch {
  my ($self, $branch, $file) = @_;
  $file =~ s#/+#/#g;
  my @yml  = $self->git(0, 1, 'show', "$branch:$file");
  my $yaml = YAML::PP::Load(join "\n", @yml);
  return $yaml;
}


has 'current_file_content' => (
  is      => 'rw',
  isa     => 'ArrayRef',
  lazy    => 1,
  builder => '_build_current_file_content',
);

sub _build_current_file_content {
    [$_[0]->git(0, 1, 'show', $_[0]->destination_branch.':'.$_[0]->outfile)]
}

has 'latest_tag' => (
  is      => 'rw',
  isa     => 'GitTag',
  lazy    => 1,
  builder => '_build_latest_tag',
);

sub _build_latest_tag {
    my ($self)  = @_;
    my @tags    = $self->git(0, 1, "tag", "--merged", $self->destination_branch);
    $self->printlog("TAGS: @tags");
    return [sort { &Build::Rpm::verscmp($b, $a) } @tags]->[0]
}

has 'project' => (
  is       => 'ro',
  isa      => 'Str',
);

sub printlog {
  print STDOUT "$_[1]\n" if $_[0]->debug;
}

sub git {
    my ($self, $verbose, $critical, @cmd) = @_;
    my $redirect = q{};# = ($verbose) ? '' ; ' 2>/dev/null'
    my $basedir  = $self->basedir;
    my $cmd = "\\git -C $basedir @cmd".$redirect;
    $self->printlog("Running command: '$cmd'");
    my @result = `$cmd`;
    if ($?) {
      warn "Failed to run command '$cmd': $?\n";
      if ($critical) {
        print "Please check if this was a critical error!\n";
        print "Would you like to proceed? [yN]\n";
	my $answer = <STDIN>;
	chomp($answer);
        if ($answer !~ /^y(es)?$/) {
	  die "Exiting ....\n";
	}
	print "Proceeding ...\n";
      }
    }
    chomp @result;
    return @result;
}

sub msg {
  my ($self, $msg) = @_;
  print STDOUT "$msg\n";
}

sub check_git_status {
  my ($self)  = @_;
  my @status = $self->git(0, 1, 'status', '--short', '--untracked=no');

  return scalar(@status);
}

sub git_hash {
  my ($self, $ref, $crit)  = @_;
  my ($r) = $self->git(0, $crit, 'log', '-1', $ref, '--pretty=%H');
  chomp $r;
  die "No valid hash found" unless $r;
  return $r;
}

sub gen_entries {
  my ($self, $entry, $indent) = @_;
  if ((ref($entry)||q{}) eq 'ARRAY') {
    my $result = q{};
    for my $sub_entry (@{$entry}) {
      $result .= $self->gen_entries($sub_entry, $indent+2);
    }
    return $result;
  } else {
    return q{ } x $indent . "* $entry\n";
  }
}

sub current_branch {
  my ($self) = @_;
  my ($current_branch) = $self->git(0, 1, 'branch', '--show-current');
  chomp($current_branch);
  return $current_branch;
}

sub dialog {
   my ($self, @lines) = @_;
   my $opts = ( ref($lines[-1]) eq 'HASH') ? pop @lines : {};
   chomp @lines;
   my $txt = join "\n", @lines;
   my $sel_txt = (ref($opts->{selection}) eq 'HASH')
                 ? 'Please select: ['.(join '|', keys %{$opts->{selection}||{}}).']'."\n"
		 : q{};
   my $def_txt = ($opts->{default}) ? "Default: '$opts->{default}'\n" : q{};
   print "$txt\n$sel_txt$def_txt";
   while (1) {
     my $ans = <STDIN>;
     chomp $ans;
     return $opts->{default} if ($opts->{default} && !$ans);

     if ($opts->{selection}) {
       while (my ($sel, $regex) = each(%{$opts->{selection}})) {
	 return $sel if $ans =~ m#^$regex$#;
       }
       print "Unknown answer!\n";
       print "Please select: $sel_txt " if $sel_txt;
     } else {
       return $ans;
     }
  }
}

sub git_last_log {
   my ($self, $branch, $lines) = @_;
   return $self->git(0, 1, 'log', "-$lines", "$branch");
}

1;
