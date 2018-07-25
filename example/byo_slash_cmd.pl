#!/usr/bin/env perl

use strict;
use warnings;

use feature qw(postderef say);
no warnings qw(experimental::postderef);

use Getopt::Long;
use FindBin qw/$Bin/;
use lib qq[$Bin/../lib];

use AnyEvent;
use AnyEvent::HipChat::Api;
use AnyEvent::HipChat;

our @LOG_LEVELS        = qw/trace debug info warning error/;
our $DEFAULT_LOG_LEVEL = 'info';

my ($interface, $port, $help, $log_level, $token, $hipchat, $hipchat_url);
GetOptions(
    "interface|i=s"   => \$interface,
    "port|p=i"        => \$port,
    "help|h"          => \$help,
    "log_level|l=s"   => \$log_level,
    "token|t=s"       => \$token,
    "hipchat|s=s"     => \$hipchat,
    "hipchat_url|u=s" => \$hipchat_url,
) or die "Error in argument list, exit\n";

$port ||= 65500;
$log_level = $DEFAULT_LOG_LEVEL if not $log_level or !grep($_ eq $log_level, @LOG_LEVELS);
eval "use Log::Any::Adapter ('Stderr', log_level => '$log_level' );1"
  or die "Cannot setup Log::Any::Adapter: $@";
if ($hipchat_url and $hipchat_url =~ m{(https?://[^/]+).*/room/.*?auth_token=(\w+)}) {
    $hipchat = $1;
    $token   = $2;
}
HELP_MESSAGE() unless $interface and $token and $hipchat;
HELP_MESSAGE() if $help;

my $hp = AnyEvent::HipChat->new(
    webhook_iface => $interface,
    webhook_port  => $port,
);

my $api = AnyEvent::HipChat::Api->new(
    hipchat_host => $hipchat,
    token        => $token,
);

my %comands = (
    ping       => { path => '', param => q[-c 4] },
    traceroute => { path => '', param => '' },
    cal        => { path => '', param => '' },
);

for my $k (keys %comands) {
    unless ($comands{$k}{path}) {
        $comands{$k}{path} = qx/which $k/;
        chomp($comands{$k}{path});
    }
}

sub cmd_help {
    <<END;
Availibale command: @{[keys %comands]}
END

}

sub send_notify {
    my $room_id = shift;
    my $msg     = shift;
    my $color   = shift;
    $api->send_room_notification(
        room_id => $room_id,
        message => $msg,
        ($color ? (color => qq[$color]) : ()),
        message_format => q[text],
        sub {
            my ($ok, $data, $err) = @_;
            if (!$ok) {
                $hp->log->error("Can't send message to room $room_id: $err");
            }
        }
    );
}

$hp->setup_callback(
    run => sub {
        my ($ok, $data, $err) = @_;
        if ($ok) {
            my $room_id = $data->{item}{room}{id};
            my $msg     = $data->{item}{message}{message};
            $help = 1;
            if ($msg =~ m{^/run (\w+)( [\w.]+)?$}) {
                my ($cmd, $par) = ($1, $2 || "");
                if (exists $comands{$cmd}) {
                    $help = 0;
                    my $cmd = qq[$comands{$cmd}{path} $comands{$cmd}{param} $par 2>&1];
                    $hp->log->debug("Execute: $cmd");
                    my $res = qx/$cmd/;
                    send_notify($room_id, "\$$cmd\n\n$res", $? ? 'red' : 'green');
                }
            }
            send_notify($room_id, cmd_help(), 'yellow') if ($help);
        }
    }
);

$hp->log->info(" *** Configure you hipchat with /cmd url: http://$interface:$port/user_callback/run");

$hp->start;

sub HELP_MESSAGE {
    my ($n) = $0 =~ m{([^/]+$)};
    print <<"HELP";

$n - Add slash command to your hipchat installation, via "Build your own" (BYO) add-on mechanix.

- Goto your hipchat installtion, click to "Add-on" -> "Build You Own Add-n"
- Choose room, bot name and create bot
- Copy posting url, set in to "$0 -u" options
- Configure YOUR COMMANDS, add slash command and set url to http://<intrface>:<port>/user_callback/run
- Run $0 and use your slash command functionality

Usage: $n  -i <interface> -p <port> [-s <hipchat> -t <token> | -u <url>] -l <log level> -h
   -i listen interface, required
   -p listen port, default $port
   -s hipchat api endpoint, required (something like http://my-hipchat-inst.org/)
   -t token, required
   -u url from hipchat configuration box (something like
      https://my-hipchat-inst.org/v2/room/2/notification?auth_token=ZZZZ)
      use it as alternative to hipchat && token
   -l log level, one of [@{[join ', ', @LOG_LEVELS]}], default: $DEFAULT_LOG_LEVEL
   -h print this message

HELP
    exit;
}
