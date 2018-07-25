#!/usr/bin/env perl

use strict;
use warnings;
use feature qw(postderef say);
no warnings qw(experimental::postderef);

use Getopt::Std;
use FindBin qw/$Bin/;
use lib qq[$Bin/../lib];

use AnyEvent;
use AnyEvent::HipChat::Api;

$| = 1;

our @LOG_LEVELS        = qw/trace debug info warning error/;
our $DEFAULT_LOG_LEVEL = 'info';
our ($opt_t, $opt_s, $opt_l, $opt_m, $opt_e, $opt_i);
getopts("t:s:l:m:i:e") or HELP_MESSAGE();

do { $opt_m = "localtime()"; $opt_e = 1 } unless $opt_m;
$opt_l = $DEFAULT_LOG_LEVEL if not $opt_l or !grep($_ eq $opt_l, @LOG_LEVELS);
$opt_i ||= 0;
eval "use Log::Any::Adapter ('Stderr', log_level => '$opt_l' );1" or die "Cannot setup Log::Any::Adapter: $@";
my $msg_sub = $opt_e ? sub { eval "$opt_m" } : sub { $opt_m };

HELP_MESSAGE() and exit unless $opt_t and $opt_s;

my $api = AnyEvent::HipChat::Api->new(
    token        => $opt_t,
    hipchat_host => $opt_s,
);

my $choose_w;
my $cv = AnyEvent->condvar;

$cv->begin;
$api->get_all_rooms(
    sub {
        my ($ok, $data, $err) = @_;
        if ($ok) {
            my @rid;
            for my $itm ($data->{items}->@*) {
                my $cid = $itm->{id};
                my $n   = $itm->{name};
                $api->log->info("room $cid: $n");
                push @rid, $cid;
            }
            if (@rid) {
                $cv->begin;
                $choose_w = choose_room($cv, @rid, sub { send_msg($cv, $api, $msg_sub, $opt_i, @_) });
            }
        }
        $cv->end;
    }
);

$cv->recv;

sub send_msg {
    my ($cv, $api, $msg_sub, $interval, $room_id) = @_;

    for my $rid (@$room_id) {
        $cv->begin;
        my $w;
        $w = AnyEvent->timer(
            after    => 0,
            interval => $interval,
            cb       => sub {
                $api->send_message(
                    room_id => $rid,
                    message => scalar $msg_sub->(),
                    sub {
                        unless ($interval) {
                            undef $w;
                            $cv->end;
                        }
                    }
                );
            }
        );
    }
}

sub choose_room {
    my $cb = pop;
    my ($cv, @rid) = @_;
    my $rid = join '|', @rid;
    my $prompt = "Choose room ($rid|*):";
    print $prompt;
    my $w;
    $w = AnyEvent->io(
        fh   => \*STDIN,
        poll => 'r',
        cb   => sub {
            chomp(my $input = <STDIN>);
            if ($input =~ /^($rid)|(\*)$/) {
                my $room_id = $1;
                if ($1) {
                    $cb->([$room_id]);
                } else {
                    $cb->([@rid]);
                }
                undef $choose_w;
                $cv->end;
            } else {
                print $prompt;
            }
        }
    );
    $w;
}

sub HELP_MESSAGE {
    my ($n) = $0 =~ m{([^/]+$)};
    print <<"HELP";

$n - send onetime/periodic message to chosen rooms with user token.

Usage: $n -s <hipchat api endpoint> -t <user token> -l <log level> -m <message> -e -i <interval>
   -s hipchat api endpoint
   -t user token
   -l log level, one of [@{[join ', ', @LOG_LEVELS]}], default: $DEFAULT_LOG_LEVEL
   -m message to send
   -e evaluate message through perl "eval", e.g. eval "localtime()"
   -i interval to send message, if omitted message was sent one time

HELP

    exit;
}
