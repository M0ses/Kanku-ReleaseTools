package Kanku::ReleaseTools::Changelog;

use strict;
use warnings;
use Moose;
use YAML::PP;
use Build::Rpm;
use Data::Dumper;  
use DateTime;

has 'outfile' => (
  is  => 'ro',
  isa => 'Str',
  required => 1,
);

with 'Kanku::ReleaseTools::Role';

has 'new_releases' => (
  is      => 'rw',
  isa     => 'ArrayRef',
  lazy    => 1,
  default => sub {
    my ($self) = @_;
    my @new_revs;
    my $changelog_rev = $self->find_latest_release_in_changelog;
    die "Could not find latest release: ".$self->outfile unless $changelog_rev;
    print "COMP: ($changelog_rev)\n";
    for my $r (@{$self->current_releases}) {
      my $cmp = &Build::Rpm::verscmp($changelog_rev, $r);
      print "COMP: ($r, $changelog_rev, $cmp)\n";
      if ($cmp < 0) {
	push @new_revs, $r;
      }
    }
    return \@new_revs;
  },
);

has 'current_releases' => (
  is      => 'rw',
  isa     => 'ArrayRef',
  lazy    => 1,
  default => sub {
    my ($self) = @_;
    my $rnotes = $self->blog_releases;
    return [sort { &Build::Rpm::verscmp($a, $b) } keys %{$rnotes}];
  },
);

has 'format' => (
  is          => 'ro',
  isa         => 'Str',
  default     => 'Default',
);

has '_new_changelog_entries' => (
  is          => 'rw',
  isa         => 'Str',
  lazy        => 1,
  default     => q{},
);

has 'format2sub' => (
  is          => 'ro',
  isa         => 'HashRef',
  default     => sub {
    {
      # kanku (0.16.2) unstable; urgency=medium
      #
      #   * updated to upstream version 0.16.2
      #  
      #   -- Frank Schreiner <fschreiner@suse.de>  Tue, 13 Feb 2024 18:24:12 +0100
      'Debian' => {
	hl     => sub {
	  my ($self, %opts) = @_;
	  return 
	    "$opts{project} ($opts{release}) unstable; urgency=medium\n\n".
            "  * updated to upstream version $opts{release}\n"
	  ;
	},
	sh     => sub { 
	  my ($self, %opts) = @_;
	  return "    * $opts{section_header}\n";
	},
	footer => sub {
	  my $fn  = $::ENV{DEBFULLNAME} || $::ENV{NAME} || die "Set DEBFULLNAME or NAME in your ENV";
	  my $em  = $::ENV{DEBEMAIL} || $::ENV{EMAIL} || die "Set DEBEMAIL or EMAIL in your ENV";
	  my $now = DateTime->now();
	  my $dat = $now->strftime('%a, %d %b %Y %H:%M:%S %z');
	  return "\n  -- $fn <$em>  $dat\n\n"
       	},
	chl    => sub { 
	  my ($self,%opts) = @_;
	  my @lines = split /\n/, $opts{text};
	  my $fl = shift @lines;
	  my $text=q{};
	  if (@lines) {
	    my @ol = map { q{ } x ($opts{indent} + 2) . "$_" } @lines;
	    $text = join "\n", @ol, q{};
	  }
          return q{ } x $opts{indent} . "* $fl\n$text";
	},
	flric  => sub { 
	  my ($self) = @_;
          for ($self->current_changelog_content) {
            return $+{release} if (m/^\S+\s+\((?<release>\d+\.\d+\.\d+)\).*/);
          }
	  die "no release found in '".$self->outfile."':\n".$self->current_changelog_content;
	},
	_indent => 6,
      },
      #-------------------------------------------------------------------
      # Tue Feb 13 17:44:07 UTC 2024 - FSchreiner@suse.com
      # 
      # - Update to version 0.16.2:
      #   * [doc] updated changelog ver: 0.16.2
      #   * [dist] updated debian files to version 0.16.2
      #   * [dist] moved tmpfile conf to package kanku-common-server
      #   * [dist] fixed homedir path for user kankurun
      #   * [handler] CreateDomain: added template to gui_config
      #   * cleanup POD in Kanku/Handler/CreateDomain
      #
      'Rpm' => {
	hl     => sub { 
	  my ($self, %opts) = @_;


	  my $fn = $::ENV{VC_REALNAME} || q{};
	  my $em = $::ENV{VC_MAILADDR} || q{};
	  my $now = DateTime->now();
	  $now->set_time_zone('UTC');
	  my $dat = $now->strftime('%a %b %d %H:%M:%S %Z %Y');
	  return "-------------------------------------------------------------------\n".
                 " $dat - $fn <$em>\n\n".
                 " - Update to version $opts{release}:\n"
          ;		 
       	},
	sh     => sub { 
	  my ($self, %opts) = @_;
	  return "   * $opts{section_header}\n";
	},
	footer => sub { 
	  my ($self, %opts) = @_;
	  return "\n";
	},
	chl    => sub {
	  my ($self,%opts) = @_;
	  my @lines = split /\n/, $opts{text};
          my $fl = shift @lines;
          my $text=q{};
          if (@lines) {
            my @ol = map { q{ } x ($opts{indent} + 2) . "$_" } @lines;
            $text = join "\n", @ol, q{};
            print Dumper($text, \@ol, \@lines);
          }

          return q{ } x $opts{indent} . "* $fl\n$text";
        },
	flric  => sub { 
	  my ($self) = @_;
          for ($self->current_changelog_content) {
            return $+{release} if (m/^- Update to version (?<release>\d+\.\d+\.\d+):$/);
          }
	  die "no release found in '".$self->outfile."':\n".$self->current_changelog_content;
	},
	_indent => 5,
      },
      'Default' => {
	hl     => sub { 
	  my ($self, %opts) = @_;
	  return "# [$opts{release}] - $opts{date}\n\n";
	},
	sh     => sub {
	  my ($self, %opts) = @_;
	  return " ## $opts{section_header}\n\n";
        },
	footer => sub { 
	  my ($self, %opts) = @_;
	  return "\n\n";
	},
	chl    => sub {
	  my ($self,%opts) = @_;
	  my @lines = split /\n/, $opts{text};
          my $fl = shift @lines;
          my $text=q{};
          if (@lines) {
            my @ol = map { q{ } x ($opts{indent} + 2) . "$_" } @lines;
            $text = join "\n", @ol, q{};
            print Dumper($text, \@ol, \@lines);
          }

          return q{ } x $opts{indent} . "* $fl\n$text";
	},
	flric  => sub { 
	  my ($self) = @_;
          for ($self->current_changelog_content) {
            return $+{release} if (m/^# \[(?<release>\d+\.\d+\.\d+)\]/);
          }
	  die "no release found in '".$self->outfile."' (".$self->format."):\n".$self->current_changelog_content;
	},
	_indent => 1,
      },
    },
  },
);

sub update {
  my ($self) = @_;
  $self->printlog(
    "##### ".$self->outpath."\n\n".
    $self->create_new_changelog_entries
  );
  return $self->outfile;
}

sub current_changelog_content{
  my ($self) = @_;
  my $b = $self->destination_branch;
  my @cl = @{$self->current_file_content};
use Data::Dumper;
print Dumper(\@cl);
  return wantarray ? @cl : join "\n", @cl;
}

sub find_latest_release_in_changelog {
  my ($self) = @_;
  my $sub = $self->format2sub->{$self->format}->{flric};
  return $sub->($self);
}

sub write_new_changelog {
  my ($self) = @_;
  my $fn     = $self->outpath;
  my $log    = $self->_new_changelog_entries;
  open(my $fh, '>', $fn) || die "Cannot open $fn: $!";
  print $fh $log || die "Could not write to $fn: $!";
  close $fh || die "Could not close $fn: $!\n";
  return $self->outfile;
}

sub gen_entries {
  my ($self, $entry, $indent) = @_;
  my $chl = $self->format2sub->{$self->format}->{chl};
  if ((ref($entry)||q{}) eq 'ARRAY') {
    my $result = q{};
    for my $sub_entry (@{$entry}) {
      $result .= $self->gen_entries($sub_entry, $indent+2);
    }
    return $result;
  } else {
    return $chl->($self, indent => $indent, text => $entry);
  }
}

sub create_new_changelog_entries {
  my ($self)   = @_;
  my $rnotes   = $self->blog_releases();
  my $log      = $self->current_changelog_content;
  my $headline = $self->format2sub->{$self->format}->{hl};
  my $sec_head = $self->format2sub->{$self->format}->{sh};
  my $footer   = $self->format2sub->{$self->format}->{footer};
  my $indent   = $self->format2sub->{$self->format}->{_indent};
  my $new_rel  = $self->new_releases;
  my $branch   = $self->cfg->conf->{blog}->{source_branch};
  for my $ver (@{$new_rel}) {
    my $file     = $self->cfg->conf->{blog}->{blogdir}.'/'.$rnotes->{$ver};
    my $yaml = $self->load_yaml_from_branch($branch, $file);
    my $d    = $yaml->{data};
    my ($date, $time) = split(/\s+/, $yaml->{date});
    my $news = $headline->(
		$self, 
		  date=>$date,
		  release=>$d->{release},
		  project => $self->project,
               );
    for my $section ('features', 'fixes') {
      next unless @{$d->{$section}||[]};
      $news .= $sec_head->(
	         $self,
		 section_header => $self->headers->{$section}
	       );
      for my $entry (@{$d->{$section}||[]}) {
        $news .= $self->gen_entries($entry, $indent);
      }
    }
    $log = $news .  $footer->($self) . $log ."\n";
  }
  return $self->_new_changelog_entries($log);
}

__PACKAGE__->meta->make_immutable;
1;
