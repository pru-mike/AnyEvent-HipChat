package AnyEvent::HipChat;

use strict;
use warnings;

use Carp qw/croak/;
use Try::Tiny;
use AnyEvent::HTTPD;
use Sys::Hostname ();

use AnyEvent::HipChat::Api;
use AnyEvent::HipChat::Utils qw/OK FAILED merge_descr make_rnd_str/;
use AnyEvent::HipChat::Store;
use AnyEvent::HipChat::EventEmitter;
use AnyEvent::HipChat::DataStore;

use parent qw/AnyEvent::HipChat::Base/;

use Class::Accessor::Fast q/moose-like/;

has api           => (is => 'ro', isa => 'AnyEvent::HipChat::Api');
has store         => (is => 'ro', isa => 'AnyEvent::HipChat::Store');
has event_emitter => (is => 'ro', isa => 'AnyEvent::HipChat::EventEmitter');
has httpd         => (is => 'ro', isa => 'AnyEvent::HTTPD');
has descriptor    => (is => 'ro', isa => 'HashRef');

our $VERSION = '0.1';

sub new {
    my ($class, %args) = @_;

    (
        bless {
            httpd_proto   => q[http],
            webhook_iface => (exists $args{webhook_iface} ? delete $args{webhook_iface} : undef),
            webhook_port  => (exists $args{webhook_port} ? delete $args{webhook_port} : 65500),
            httpd_args    => (exists $args{httpd_args} ? delete $args{httpd_args} : []),
        },
        $class
    )->_init(\%args);
}

sub _init {
    my ($self, $args) = @_;
    $self->{api}           = AnyEvent::HipChat::Api->new();
    $self->{event_emitter} = AnyEvent::HipChat::EventEmitter->new();
    $self->{descriptor}    = $self->_make_descriptor(delete $args->{descriptor});
    $self->SUPER::_init($args);
    $self->{store} = AnyEvent::HipChat::Store->new(
        hipchat      => $self,
        data_storage => ($args->{data_storage} || AnyEvent::HipChat::DataStore->new()),
    );
    $self->on(token_updated => sub { $self->store->save });
    $self;
}

sub on {
    my ($self, $event, $cb) = @_;
    $self->event_emitter->new_event($event => $cb);
}

sub scopes {
    shift->descriptor->{capabilities}{hipchatApiConsumer}{scopes} || [];
}

sub start {
    my $self = shift;
    die 'desriptor not defined'     unless $self->{descriptor};
    die 'webhook_iface not defined' unless $self->{webhook_iface};

    my $h = AnyEvent::HTTPD->new(
        host => $self->{webhook_iface},
        port => $self->{webhook_port},
        @{ $self->{httpd_args} }
    );
    my %routing = (
        '/install'       => sub { _install($self,       @_) },
        '/callback_url'  => sub { _callback_url($self,  @_) },
        '/uninstall'     => sub { _uninstall($self,     @_) },
        '/user_callback' => sub { _user_callback($self, @_) },
    );
    $h->reg_cb(%routing);

    $self->{httpd} = $h;
    $self->log->infof("Starting server %s", $self->_webhook_url);
    $self->log->debug("with routes: " . join ', ', keys %routing);
    $self->httpd->run;
}

sub setup_callback {
    my $cb      = pop;
    my $self    = shift;
    my $req_key = shift;
    if ($req_key and $req_key !~ /^\w+$/) {
        croak "Wrong user_callback format $req_key, must be ^\\w+\$";
    }
    $req_key ||= $self->make_rnd_str;
    my $cb_url = $self->_webhook_url . q[/user_callback/] . $req_key;
    $self->event_emitter->new_user_event($req_key => $cb);
    return $cb_url;
}

sub _install {
    my ($self, $httpd, $req) = @_;
    $self->log->debugf(" --> %s:/install", $req->method);
    $req->respond({
            content => ['application/json', $self->encode_json($self->descriptor)]
        }
    );
}

sub _uninstall {
    my ($self, $httpd, $req) = @_;
    my $uninst_url = $req->parm('installable_url');
    my $return_url = $req->parm('redirect_url');
    $self->log->debugf(" --> %s:/uninstall [%s]", $req->method, $uninst_url);
    if ($uninst_url) {
        $self->api->universal_req(
            GET => $uninst_url,
            sub {
                my ($ok, $data, $err) = @_;
                if (!$ok) {
                    $err = "Cannot uninstall add-on: $err";
                    $self->log->error($err);
                    $req->respond({ content => ['text/plain', $err] });
                } else {
                    $self->store->uninstall($data);
                    if ($return_url) {
                        $req->respond({ redirect => $return_url });
                    } else {
                        $req->respond({ content => ['text/plain', 'uninstalled'] });
                    }
                }
            }
        );
    } else {
        my $err = "Cannot uninstall add-on, there is no 'installable_url' from hipchat";
        $self->log->error($err);
        $req->respond({ content => ['text/plain', $err] });
    }
}

sub _callback_url {
    my ($self, $httpd, $req) = @_;
    my $json = $req->content;
    $self->log->debugf(" --> %s:/callback_url: %s", $req->method, $json);
    $req->respond({
            content => []
        }
    );
    my $data;
    try {
        $data = $self->decode_json($json);
    }
    finally {
        if (@_) {
            $self->error("Unable to decode incoming message: $json");
        } else {
            $self->store->new_installation(data => $data,)->get_capabilities_document();
        }
    };
}

sub _user_callback {
    my ($self, $httpd, $req) = @_;
    my $json = $req->content;
    my $url  = $req->url->path;
    $self->log->debugf(" --> %s:%s: %s", $req->method, $url, $json);
    $req->respond({
            content => []
        }
    );
    my $req_key = undef;
    if ($url =~ m{/user_callback/(\w+)}) {
        $req_key = $1;
    }
    my $data;
    try {
        $data = $self->decode_json($json);
    }
    finally {
        if (@_) {
            my $err = "Unable to decode incoming message: $json";
            $self->log->error($err);
            $self->event_emitter->fire_user_event($req_key => FAILED, undef, $err);
        } else {
            $self->event_emitter->fire_user_event($req_key => OK, $data);
        }
    };
}

sub _make_descriptor {
    my ($self, $descr_config) = @_;
    my $descr_default = {
        name        => ucfirst(lc(Sys::Hostname::hostname)) . " hipchat integration",
        description => 'An integration that make cool stuff',
        key         => Sys::Hostname::hostname,
        links       => {
            self => $self->_webhook_url . '/install',
        },
        capabilities => {
            hipchatApiConsumer => {
                scopes => [qw/send_message/]
            },
            "installable" => {
                "callbackUrl"    => $self->_webhook_url . '/callback_url',
                "uninstalledUrl" => $self->_webhook_url . '/uninstall',
            },
        }
    };
    merge_descr(\$descr_config => \$descr_default) if ($descr_config);
    $descr_default;
}

sub _webhook_url {
    my $self = shift;
    sprintf("%s://%s:%s", $self->{httpd_proto}, $self->{webhook_iface} || "", $self->{webhook_port} || "");
}

1;

=pod

=head1 NAME

AnyEvent::HipChat - Build application to Atlassian Hipchat

=head1 SYNOPSIS

    my $hp = AnyEvent::HipChat->new(
        webhook_iface => $interface,
        webhook_port  => $port,
        data_storage  => <storage class, optional>,
        descriptor    => <hipchat capabilities descriptor>
    );

    $hp->on(
       ready => sub {
           my $store = shift;
           my $room_id = $store->room_id;
           my $api = $store->api;
           .... #doing something very useful here
       }
    );

    $hp->start;

=head1 DESCRIPTION

Framework to build application to Atlassian Hipchat platform.
It's contain two major parts: L<AnyEvent::HipChat::Api> - api client library,
L<AnyEvent::HipChat> - hipchat http callback handler.

=head1 USAGE

Basic usage scenario

=over

=item setup

Provide interface, prort and capabilities descriptor to L<AnyEvent::HipChat> constructor

=item on->ready

Setup some callbacks with very useful scenario via B<ready> event

=item setup_callback

Setup some user defined callback handlers (e.g. for room message processing)

=item start

Make L<AnyEvent::HipChat> framework to listen hipchat callback.

=back

=head1 METHODS

=head2 new(%args)

Constructor, provide following options:

=over

=item webhook_iface, required

Listening interface address, B<required>
There is no default, and it MUST be real
network interface no 0.0.0.0.

=item webhook_port

B<AnyEvent::Hipchat> port, default B<65500>

=item httpd_args

Something that you wand to send to B<AnyEvent::HTTPD->new(...)>

=item descriptor

Hipchat capability descriptor goes here.
Note that there is reasonable default

   {
        name         => ucfirst(lc(Sys::Hostname::hostname)). " hipchat integration",
        description  => 'An integration that make cool stuff',
        key          => Sys::Hostname::hostname,
        links        => { ... },
        capabilities => {
            hipchatApiConsumer => {
                scopes => [
                    qw/send_message/
                ]
            },
            "installable" => { ... },
        }
    };

=item data_storage

Instanse of class that support L<AnyEvent::HipChat::DataStore> interface

=back

=head2 on($event => $sub)

  $hp->on(reday => sub { .... })

Setup new event handler, for now only 'ready' event effectively supported

=head2 setup_callback($sub)

  my $cb_url =
      $hp->setup_callback(sub {
          my ($ok, $data, $err) = @_;
          ...
      });

  $api->create_room_webhook(
      url => $cb_url,
      event => 'room_message',
      room_id => $room_id,
      key => $room_hook_key,
      sub {
          my ($ok, $data, $err) = @_;
          ...
   });

Setup user defined callback

=head2 start()

Register callbacks and run L<AnyEvent::HTTPD> on configured host/port

=head2 scopes()

Get scopes from capabilities descriptor

=head1 api, store, event_emitter, httpd, descriptor

Various accessors

=head1 AUTHORS

pru.mike@gmail.com

=head1 LICENSE

CC0 1.0 Universal

=head1 SEE ALSO

B<examples/>, L<AnyEvent::HipChat::Api>,
L<AnyEvent::HipChat::EventEmitter>, L<AnyEvent::HTTPD>,
L<AnyEvent::HipChat::DataStore>

=cut
