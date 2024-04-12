#!/usr/bin/perl

use strict;
use warnings;
use Test::More;
use FindBin;

BEGIN { push @::INC, "/usr/lib/build", "$FindBin::Bin/../lib"; };

plan tests => 6;

use_ok 'Kanku::ReleaseTools';
use_ok 'Kanku::ReleaseTools::Role';
use_ok 'Kanku::ReleaseTools::BlogPost';
use_ok 'Kanku::ReleaseTools::ReleaseNotes';
use_ok 'Kanku::ReleaseTools::Changelog';
use_ok 'Kanku::ReleaseTools::VersionReplace';

exit 0;
