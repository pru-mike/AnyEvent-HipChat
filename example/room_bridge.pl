#!/usr/bin/env perl

use strict;
use warnings;

use feature qw(postderef say);
no warnings qw(experimental::postderef);

use Getopt::Long;
use FindBin qw/$Bin/;
use lib qq[$Bin/../lib];

use AnyEvent;
use AnyEvent::HipChat;
use AnyEvent::HipChat::DataStore::File;

our @LOG_LEVELS        = qw/trace debug info warning error/;
our $DEFAULT_LOG_LEVEL = 'info';

my ($interface, $store_file, $port, $help, $log_level);
GetOptions(
    "interface|i=s"  => \$interface,
    "port|p=i"       => \$port,
    "store_file|f=s" => \$store_file,
    "help|h"         => \$help,
    "log_level|l=s"  => \$log_level,
) or die "Error in argument list, exit\n";

$store_file ||= "installations_store.json";
$port       ||= 65500;
$log_level = $DEFAULT_LOG_LEVEL if not $log_level or !grep($_ eq $log_level, @LOG_LEVELS);
eval "use Log::Any::Adapter ('Stderr', log_level => '$log_level' );1"
  or die "Cannot setup Log::Any::Adapter: $@";
HELP_MESSAGE() unless $interface;
HELP_MESSAGE() if $help;

my $hp = AnyEvent::HipChat->new(
    webhook_iface => $interface,
    webhook_port  => $port,
    data_storage  => AnyEvent::HipChat::DataStore::File->new(file_name => $store_file),
    descriptor    => {
        capabilities => {
            hipchatApiConsumer => {
                scopes => [qw/view_messages send_notification/]
            },
        }
    }
);

my %rooms;

$hp->on(
    ready => sub {
        my $store = shift;

        my $rid = $store->room_id;
        $rooms{$rid} = $store;
        my $cb_url = $hp->setup_callback(
            sub {
                my ($ok, $data, $err) = @_;
                my $msg            = $data->{item}{message}{message};
                my $from_user      = $data->{item}{message}{from}{name};
                my $from_room      = $data->{item}{room}{id};
                my $from_room_name = $data->{item}{room}{name};
                if ($ok) {
                    for my $room (keys %rooms) {
                        my ($rid, $store) = ($room, $rooms{$room});
                        next if $rid == $from_room;
                        $hp->log->debug(
                            "Try to send message \"$msg\" to room \"$rid\" from \"$from_room($from_room_name)\"");
                        $store->api->send_room_notification(
                            room_id        => $rid,
                            message        => "$from_user($from_room_name): " . $msg,
                            message_format => q[text],
                            sub {
                                my ($ok, $data, $err) = @_;
                                if (!$ok) {
                                    $hp->log->error("Can't send message to room $_: $err");
                                }
                            }
                        );
                    }
                }
            }
        );

        $store->api->create_room_webhook(
            room_id => $rid,
            key     => $store->next_room_key,
            url     => $cb_url,
            event   => 'room_message',
            sub {
                my ($ok, $data, $err) = @_;
                if (!$ok) {
                    $hp->log->error("Can't create room $rid web hook: $err");
                }
            }
        );
    }
);

$hp->log->info("Loading saved events from file: $store_file");
if ($hp->store->load) {
    $hp->store->issue_token;
}

$hp->start;

sub HELP_MESSAGE {
    my ($n) = $0 =~ m{([^/]+$)};
    print <<"HELP";

$n - make a bridge between hipchat rooms.

1) Start program
2) Goto your hipchat interface
3) Install application via "Install an add-on from a descriptor URL" into several rooms,
   use address http://<interface:port>/install

Then robot will duplicate message send into one room, into another

Usage: $n -i <interface> -p <port> -f <store file> -h
   -i listen interface, required
   -p listen port, default $port
   -f store file, default $store_file
   -l log level, one of [@{[join ', ', @LOG_LEVELS]}], default: $DEFAULT_LOG_LEVEL
   -h print this message

HELP

    exit;
}
