#!/usr/bin/env perl

use strict;
use warnings;
use FindBin qw/$Bin/;
use lib qq[$Bin/../lib];
use Test::More tests => 10;

use_ok 'AnyEvent::HipChat::Utils';
use_ok 'AnyEvent::HipChat::Base';
use_ok 'AnyEvent::HipChat::Api::InjectMethods';
use_ok 'AnyEvent::HipChat::Api';
use_ok 'AnyEvent::HipChat';
use_ok 'AnyEvent::HipChat::Store';
use_ok 'AnyEvent::HipChat::Store::Installation';
use_ok 'AnyEvent::HipChat::EventEmitter';
use_ok 'AnyEvent::HipChat::DataStore';
use_ok 'AnyEvent::HipChat::DataStore::File';
