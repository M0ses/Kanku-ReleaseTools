package Kanku::ReleaseTools::BlogPost;

use strict;
use warnings;
use Moose;


use File::Basename;
use File::Temp qw/tempfile/;
use File::Copy;
use File::Path qw/make_path/;
use DateTime;
use Build::Rpm;
use Statocles::Template;
use DateTime::Format::ISO8601;
use Cwd;
use YAML::PP;

has 'outfile' => (
  is      => 'rw',
  isa     => 'Str',
  lazy    => 1,
  builder => '_build_outfile',
);

sub _build_outfile {
    my $dt = $_[0]->release_datetime();
    my $bp = $_[0]->blog_dir."/$dt->[0]/release-".$_[0]->release."/index.md";
    $bp =~ s#/+#/#g;
    return $bp;
}

with 'Kanku::ReleaseTools::Role';

has 'log_history' => (
  is       => 'rw',
  isa      => 'ArrayRef',
  lazy     => 1,
  builder  => '_build_log_history',
);

sub _build_log_history {
   my ($self) = @_;
   my @log = $self->git(0, 1, 'log', $self->latest_tag.'..'.$self->git_hash($self->destination_branch,1));
   my $in=0;
   my $sec=0;
   my @msgs=();
   my $msg;
   for my $ll (@log) {
     if ($ll =~ /^    /) { $in || $sec++;$in = 1 };
     if ($ll =~ /^\S/) { push @msgs, $msg if $msg; $in = 0 ; $msg = q{} };
     $msg .= substr($ll,4) if ($in && $ll && length($ll)>4);
   }
   chomp @msgs;
   return \@msgs;
}

has 'categorized_log' => (
  is       => 'rw',
  isa      => 'HashRef',
  lazy     => 1,
  builder  => '_build_categorized_log',
);

sub _build_categorized_log {
  my ($self) = @_;
  my $result = {
       warnings => [],
       features => [],
       fixes    => [],
       examples => [],
       ''       => [],
     };

  for my $log_entry (@{$self->log_history}) {
    my @ll = split(/\n/, $log_entry);
    my $cat = q{};
    my $cat_final;
    for my $line (@ll) {
      $cat = 'fixes' if (!$cat_final && $line =~ /fix(ed|es)?/i);
      $cat = $2 if ( $line =~ /^cat(egory)?: (fixes|examples|features|warnings)/i);
    }
    push @{$result->{$cat}}, $log_entry;
  }
  return $result;
}


has '_blog_post_text' => (
  is       => 'rw',
  isa      => 'Str',
  lazy     => 1,
  default  => q{},
);

has 'blogurl' => (
  is       => 'rw',
  isa      => 'Str',
);

has '_ready_to_commit' => (
  is       => 'rw',
  isa      => 'Bool',
  default  => 0,
);

has 'release_datetime' => (
  is       => 'rw',
  isa      => 'ArrayRef',
  builder  => '_build_release_datetime',
);

sub _build_release_datetime {
  my ($self) = @_;
  my $br     = $self->blog_releases;
  my $rel    = $self->release;
  die unless $rel;
  my $bp     = $br->{$rel} || q{};
  my $now;

  if ($bp) {
    my $bf  = $self->cfg->conf->{blog}->{blogdir}.'/'.$bp;
    my $bb  = $self->cfg->conf->{blog}->{source_branch};
    my $yml = $self->load_yaml_from_branch($bb, $bf);
       
    $now = $self->_create_dt_object_from_string($yml->{date});
  } else { 
    
    $now = DateTime->now();

    my $answer = $self->dialog(
      "\nDefault release time/date: ".$now->datetime(q{ })."\n".
      "Please enter the correct release date/time in the given format.\n".
      "(FORMAT: YYYY-MM-DD hh:mm:ss)\n" .
      "Or press ENTER to accept the default.\n\n"
    );

    while ($answer) {
      $answer =~ s/^\s*(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s*(.*)\s*$/$1T$2$3/;
      eval {
          $now = $self->_create_dt_object_from_string($answer);
      };  
      if ($@) {
	$answer = $self->dialog(
		    "Wrong date/time format: $@\n".
		    "Please retry or press enter to use default (now)\n"
		  );
      } else {
	last;
      }
    }
  }
  return [$now->ymd('/'), $now->ymd." ".$now->hms];
}

sub _create_dt_object_from_string {
  my ($self, $str) = @_;
  $str =~ s/^\s*(\d{4}-\d{2}-\d{2})\s+(\d{2}:\d{2}:\d{2})\s*(.*)\s*$/$1T$2$3/;
  return DateTime::Format::ISO8601->parse_datetime($str);
}

sub check_git_status {
  my ($self)  = @_;
  my @status = $self->git(0, 1, 'status', '--short', '--untracked=no');

  return scalar(@status);
}

sub release_tag_hash {
  my ($self)  = @_;
  return $self->git_hash($self->release, 0);
}

sub create_blog_post {
  my ($self)       = @_;
  my $dt           = $self->release_datetime();
  my $version      = $self->release;
  my $prev_version = $self->latest_tag;
  my $git_log      = $self->log_history;
  my $log_by_cat   = $self->categorized_log;

  my $templ        = Statocles::Template->new(
    # FIXME: make configurable in .krt.yml
    path => $self->basedir.'/'.$self->blog_dir."/release-template.tt2",
  );

  return $self->_blog_post_text(
    $templ->render(
      version => $self->release,
      date    => $dt->[1],
      logs    => $self->categorized_log,
    )
  );
}

sub already_exists {
  my ($self)  = @_;
  my $op = $self->outpath;
  $self->printlog("Checking $op"); 
  return (-f $op) ? 1 : 0;
}

sub write_blog_post {
  my ($self)  = @_;
  my ($fh, $filename) = tempfile();
  $self->printlog("Writing temp file $filename\n");
  print $fh $self->_blog_post_text || die "Error while writing to file '$filename': $!";
  close $fh || die "Could not close $filename: $!";

  while (1) {
    $self->edit_file($filename);
    eval { YAML::PP::LoadFile($filename) };
    if ($@) {
      print STDERR "Could not load yaml file $filename: $@";
      my $ans = $self->dialog("Retry? [Yn]");
      die "Cannot procceed with broken yaml file!" if ($ans =~ /^n/i);
    } else {
      last;
    }
  }

  my $outfile = $self->outpath;
  my $ans = $self->dialog("Really create file $outfile? [yN] ");
  if ($ans =~ /^y(es)?$/i) {
    my $dir = dirname($outfile);
    make_path($dir) unless -d $dir;
    $self->printlog("Copying $filename -> $outfile\n");
    copy($filename, $outfile) || die "Copying failed $filename -> $outfile: $!";
    $self->_ready_to_commit(1);
  } else {
    $self->printlog("Skipped creation of $outfile!\n");
  }
}

sub edit_existing_blog_post {
  my ($self) = @_;
  $self->edit_file($self->outpath);
  $self->_ready_to_commit(1);
  return;
}

sub edit_file {
  my ($self, $fn) = @_;
  die "No EDITOR set in ENV" unless $::ENV{'EDITOR'};
  while (1) {
    system("$::ENV{'EDITOR'} $fn");
    my $a = $self->dialog(
      "How to procceed?",
      " * r - restart editor",
      " * p - print file content",
      " * c - continue",
      " * a - abort",
      {
	selection => {
	  'r' => 'r(estart)?',
	  'p' => 'p(rint)?',
	  'c' => 'c(ontinue)?',
	  'a' => 'a(bort)?',
	},
	default => 'c',
      },
    );
    if      ($a eq 'p') {
      $self->printfile();
    } elsif ($a eq 'e') {
      next;
    } elsif ($a eq 'c') {
      last;
    } elsif ($a eq 'a') {
      exit 2;
    }
  }
  return;
}

sub printfile {
  my ($self, $fn) = @_;
  my $infile = $fn || $self->outpath;
  open(my $fh, '<', $infile) || die "Could not open $infile: $!";
  print <$fh>;
  close($fh) || die "Could not close $infile: $!";
  return;
}

sub build_blog {
  my ($self, $preview_default, $commit_default) = @_;
  my $ans = $self->dialog(
    "Would you like to start a blog preview? [Yn] ",
    {
      selection => {
	'y' => 'y(es)?',
	'n' => 'n(o)?',
      },
      default => $preview_default,
    },
  );
  return if ($ans eq 'n');

  my $cwd = Cwd::cwd();
  chdir $self->basedir;
  $self->msg(
    "\nStarting statocles daemon.\n".
    "Once you are done with your review please\n\n".
    "PRESS <CTRL-C>\n".
    "to stop the daemon and continue releasing\n\n".
    "--- URL: ".$self->blog_post_url('http://localhost:3000')."\n\n"
  );
  system("statocles daemon");
  $self->printlog("Statocles daemon stopped");
  chdir $cwd;

  $ans = $self->dialog(
    "Would you like to commit? [Y(es)|n(o)|a(bort)] ",
    {
      selection => {
	'y' => 'y(es)?',
	'n' => 'n(o)?',
	'a' => 'a(bort)?',
      },
      default => $commit_default,
    },
  );
  exit 2 if $ans eq 'a';
  $self->_ready_to_commit(0) if $ans eq 'n';
}

sub commit_blog {
  my ($self) = @_;
  return unless $self->_ready_to_commit;
  my $cwd = Cwd::cwd();
  chdir $self->basedir;
  $self->git(0, 1, 'add', $self->outfile);
  if ($self->check_git_status) {
    my $version = $self->release;
    $self->git(0, 1, 'commit', '-m', "'created blog post for $version'");
  } else {
    $self->printlog("Nothing to commit for ".$self->outfile);
  }
  chdir $cwd;
}

sub blog_post_url {
  my ($self, $url) = @_;
  $url =~ s#/+$##;
  $url .= '/'.$self->outfile;
  $url =~ s#/index.md$#/index.html#;
  return $url;
}

sub deploy_blog {
  my ($self) = @_;
  return unless $self->_ready_to_commit;
  my $ans = $self->dialog("Would you like to deploy the new blog post? [Yn] ");
  if ( $ans !~ /^n/i ) {
    my $cwd = Cwd::cwd();
    chdir $self->basedir;
    system("statocles deploy");
    chdir $cwd;

    my $url = $self->blog_post_url($self->blogurl);

    $self->msg(
      "Check your blog: $url\n".
      "Deployed blog!\n"
    );
  } else {
    $self->printlog("Skipped blog deployment");
  }
  return;
}

__PACKAGE__->meta->make_immutable;

1;
