#!/usr/bin/env perl

use strict;
use warnings;
use FindBin qw/$Bin/;
use lib qq[$Bin/../lib];
use Test::More tests => 3;
use Test::Deep;
use Data::Dumper;
use AnyEvent::HipChat::Utils;

ok(OK, 'ok');
ok(!FAILED, 'FAILED');

my $default = {
    name    => 'XXX',
    key     => 'YYY',
    include => {
        include2 => {
            arr  => [ qw/a b c/ ],
            test1 => {
                test2 => {
                    elem2 => 2
                }
            }
        }
    }
};

my $config = {
    key     => 'ZZZ',
    include => {
        include2 => {
            arr => [ qw/d/ ],
        },
        include3  => {
           elem1 => 1
        },
    }
};

my $sample = {
    name    => 'XXX',
    key     => 'ZZZ',
    include => {
        include2 => {
            arr => [ qw/d/ ],
            test1 => {
                test2 => {
                    elem2 => 2
                }
            }
        },
        include3 => {elem1 => 1}
    }
};

AnyEvent::HipChat::Utils::merge_descr(\$config => \$default);

cmp_deeply($default => $sample, '_merge_descr');
