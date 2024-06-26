package Kanku::ReleaseTools::POD;

use Moose;

use FindBin;
use File::Path qw(make_path remove_tree);
use URI::Escape;
use Cwd;

has 'src_branch' => (
  is      => 'rw',
  isa     => 'Str',
  default => 'master',
);

has 'src_dir' => (
  is      => 'rw',
  isa     => 'Str',
  default => 'lib',
);

has 'dst_dir' => (
  is      => 'rw',
  isa     => 'Str',
  default => 'page/pod',
);

has 'basedir' => (
  is      => 'rw',
  isa     => 'Str',
  default => sub { return "$FindBin::Bin/../.." },
);

sub generate_html {
  my ($self) = @_;

  my %opts = (
    output_encoding => 'UTF-8',
    perldoc_url_prefix => './',
  );

  my $path_spec = $ARGV[0] || 'master';
  my $sdir      = $self->src_dir;
  my $curdir    = Cwd::cwd;
  my $outdir    = $self->basedir."/".$self->dst_dir;

  my @infiles = grep
                { chomp; m#$sdir/(.*)\.(pm|pod)#; }
		$self->_git(
		  'ls-tree',
		  '-r',
		  '--name-only',
		  $self->src_branch,
		  '--',
		  $self->src_dir,
		)
              ;

  my %files;
  my %podhtml_LOT;
  my @new_files;

  for (@infiles) {
    m#$sdir/([^.].*)[.](pm|pod)#;
    my $p = $1;
    my $f = "$1.$2";
    $p =~ s#/#::#g;
    $files{$p} = $f;
    my $h = uri_escape($p);
    $podhtml_LOT{$p} = "$h.html";
  }

  # Cleanup tree
  remove_tree($outdir);
  make_path($outdir);

  while (my ($package, $file) = each %files) {
    my $of = "$outdir/$package.html";
    $self->convert($file, $of, \%podhtml_LOT) &&
      push @new_files, $of;
  }

  chdir $curdir;

  return @new_files;
}

sub convert {
    my ($self, $in_file, $out_file, $podhtml_LOT) = @_;
    # Late loading to avoid problems with Pod::Simple::Debug
    require Pod::Simple::HTML;
    my $p = Pod::Simple::HTML->new;
    $p->{podhtml_LOT} = $podhtml_LOT;
    $p->html_css('../../theme/css/statocles-default.css'),
    my $html;
    $p->output_string(\$html);
    my $header = <<EOF;
        </title>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <link rel="stylesheet" href="../../theme/css/normalize.css" />
        <link rel="stylesheet" href="../../theme/css/skeleton.css" />
        <link rel="stylesheet" href="../../theme/css/statocles-default.css" />
        <link rel="stylesheet" href="//maxcdn.bootstrapcdn.com/font-awesome/4.3.0/css/font-awesome.min.css">
        <link rel="shortcut icon" type="image/x-icon" href="../favicon.ico">
        <meta name="generator" content="Statocles 0.098" />

    </head>
    <body>
        <header>
            <nav class="navbar">
                <div class="container">
                    <a class="brand" href="/">Kanku</a>
                    <ul>
                        <li>
                            <a href="../getting_started">Getting Started</a>
                        </li>
                        <li>
                            <a href="../overview">Overview</a>
                        </li>
                        <li>
                            <a href="../faq">FAQ</a>
                        </li>
                        <li>
                            <a href="../download">Download</a>
                        </li>
                        <li>
                            <a href="../../blog">News</a>
                        </li>
                    </ul>

                </div>
            </nav>

        </header>
        <div class="main container">
            <div class="row">
                <div class="nine columns">
                    <main>

EOF
    $p->html_header_after_title($header);
    my $footer=<<EOF;
                    </main>
                </div>

                <div class="three columns sidebar">



                </div>
            </div>
        </div>
        <footer>

        </footer>
    </body>
</html>
EOF
    $p->html_footer($footer);
    my $content = $self->_read_file_from_branch($in_file);
    $p->parse_string_document($content);
    if ($html) {
      my $of;
      open($of, '>', $out_file) || die "Could not open $of: $!\n";
      binmode $of, ':bytes';
      print $of $html || die "Could not write $of: $!\n";;
      close $of || die "Could not close $of: $!\n";
    } else {
      return 0;
    }
    return 1;
}

sub _read_file_from_branch {
  my ($self, $file) = @_;
  my @cmd = ('show', $self->src_branch.":lib/$file");
  my $content = $self->_git(@cmd);
  return $content;
}

sub _git {
  my ($self, @args) = @_;
  my @cmd = ('git', '-C', $self->basedir, @args);
  open(my $fh, '-|', @cmd) || die "Could not execute '@cmd': $!";
  my @content = <$fh>;
  close $fh || die "Could not finish command @cmd cleanly: $!";
  return wantarray ? @content : join('', @content);
}

1;
__END__
