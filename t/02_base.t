#!/usr/bin/env perl

use strict;
use warnings;
use FindBin qw/$Bin/;
use lib qq[$Bin/../lib];
use Test::More tests => 2;
use Test::Deep;
use Data::Dumper;
use AnyEvent::HipChat::Base;

package AnyEvent::HipChat::TestBase;

use parent q/AnyEvent::HipChat::Base/;

sub new { bless {}, shift };

package main;

my $json_str = '{"aaa":111, "bbb":{"ccc":222}}';

my $tb = AnyEvent::HipChat::TestBase->new()->_init();

my $data = $tb->decode_json($json_str);

cmp_deeply($data, {aaa => 111, bbb=> {ccc => 222}}, 'AnyEvent::HipChat::Base->decode_json');

my $str = $tb->encode_json({aaa => 123});

is($str, '{"aaa":123}', 'AnyEvent::HipChat::Base->encode_json');
