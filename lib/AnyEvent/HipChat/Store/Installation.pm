package AnyEvent::HipChat::Store::Installation;

use strict;
use warnings;

use AnyEvent;
use Scalar::Util qw/weaken/;
use Class::Accessor::Fast q/moose-like/;
use Clone qw/clone/;

use parent qw/AnyEvent::HipChat::Base/;

use overload '""' => sub { join ':', $_[0]->{oauth_id}, $_[0]->{room_id} };

has _token_issue_conf     => (is => 'ro', isa => 'Int');
has _token_issue_counter  => (is => 'rw', isa => 'Int');
has _token_issue_interval => (is => 'ro', isa => 'Int');
has _room_key             => (is => 'rw', isa => 'Int');
has hipchat               => (is => 'ro', isa => 'AnyEvent::HipChat');
has api                   => (is => 'rw', isa => 'AnyEvent::HipChat::Api');
has oauth_id         => (is => 'ro', => 'Str');
has oauth_secret     => (is => 'ro', => 'Str');
has room_id          => (is => 'ro', => 'Str');
has group_id         => (is => 'ro', => 'Str');
has capabilities_url => (is => 'ro', => 'Str');

sub new {
    my $class = shift;
    my %args  = @_;
    my $self  = {
        hipchat               => $args{hipchat},
        _token_issue_conf     => $args{token_issue_retry_count} || 3,
        _token_issue_interval => $args{token_issue_retry_interval} || 3,
        _token_issue_watcher  => undef,
        _emited               => undef,
    };
    weaken($self->{hipchat});

    for (qw/oauthId capabilitiesUrl roomId groupId oauthSecret/) {
        my $k = lc(s/([a-z]+)(.+)/$1_$2/r);
        $self->{$k} = $args{data}->{$_} || die "$_ not defined";
    }
    bless($self, $class)->_init(\%args);
}

sub ee {
    shift->hipchat->event_emitter;
}

sub _init {
    my $self = shift;
    my $args = shift;
    $self->api($self->hipchat->api);
    $self->_reset_counter;
    $self->_room_key(1);
    $self->SUPER::_init($args);
}

sub serrialize {
    my $self        = shift;
    my $object_data = {};
    $object_data->{capabilities_document} = clone($self->{capabilities_document});
    for (qw/oauthId capabilitiesUrl roomId groupId oauthSecret/) {
        my $k = lc(s/([a-z]+)(.+)/$1_$2/r);
        $object_data->{installation_data}{$_} = $self->$k;
    }
    $object_data;
}

sub deserrialize {
    my $class       = shift;
    my $object_data = shift;
    my %args        = @_;
    my $obj         = AnyEvent::HipChat::Store::Installation->new(
        data => $object_data->{installation_data},
        %args
    );
    $obj->_add_cap_doc($object_data->{capabilities_document});
    $obj;
}

sub ready {
    my $self = shift;
    if (!$self->{_emited}) {
        $self->{_emited} = 1;
        my $store_api = AnyEvent::HipChat::Api->new(
            token        => $self->token,
            hipchat_host => $self->api_url,
        );
        $self->api($store_api);
        $self->ee->fire(ready => $self);
    }
    $self->ee->fire(token_updated => $self);
}

sub _reset_issue_watcher {
    my $self = shift;
    undef $self->{_token_issue_watcher};
}

sub _reset_counter {
    my $self = shift;
    $self->_token_issue_counter($self->_token_issue_conf);
}

sub _countdown_counter {
    my $self = shift;
    $self->_token_issue_counter($self->_token_issue_counter - 1);
}

sub _add_cap_doc {
    my $self = shift;
    my $data = shift;
    $data->{capabilities}{hipchatApiProvider}{url} =~ s{/$}{};
    $self->{capabilities_document} = $data;
}

sub next_room_key {
    my $self = shift;
    my $rk   = $self->_room_key();
    $self->_room_key($rk + 1);
    return $rk;
}

sub token {
    shift->{token}{access_token};
}

sub api_url {
    shift->{capabilities_document}{capabilities}{hipchatApiProvider}{url};
}

sub token_url {
    shift->{capabilities_document}{capabilities}{oauth2Provider}{tokenUrl};
}

sub authorization_url {
    shift->{capabilities_document}{capabilities}{oauth2Provider}{authorizationUrl};
}

sub issue_token {
    my $self = shift;
    $self->_countdown_counter();
    $self->hipchat->api->issue_access_token(
        endpoint     => $self->token_url,
        scopes       => $self->hipchat->scopes,
        oauth_id     => $self->oauth_id,
        oauth_secret => $self->oauth_secret,
        sub {
            my ($ok, $data, $err) = @_;
            if (!$ok) {
                $self->log->error("Cannot issue access token for ($self): $err");
                if ($self->_token_issue_counter) {
                    $self->{_token_issue_watcher} = AnyEvent->timer(
                        after    => $self->_token_issue_interval,
                        interval => 0,
                        cb       => sub { $self->issue_token }
                    );
                } else {
                    $self->_reset_issue_watcher;
                    $self->log->errorf("Issue access token for ($self) failed with %d retry", $self->_token_issue_conf);
                }
            } else {
                $self->_reset_issue_watcher;
                $self->_reset_counter();
                $self->_update_token($data);
                $self->{_token_issue_watcher} = AnyEvent->timer(
                    after    => $self->{token}{expires_in} - 5,
                    interval => 0,
                    cb       => sub { $self->issue_token }
                );
                $self->ready();
            }
        }
    );
}

sub _update_token {
    my $self = shift;
    my $data = shift;
    for (qw/access_token token_type scope expires_in/) {
        $self->{token}{$_} = $data->{$_};
    }
    $self->{token}{time} = $data->{time} ? $data->{time} : time;
    $self->log->debugf(
        "Issue access token successful: %s %s",
        $self->{token}{access_token},
        $self->{token}{expires_in},
    );
}

sub get_capabilities_document {
    my $self = shift;
    unless ($self->capabilities_url) {
        $self->log->error("capabilitiesUrl does not defined: ($self)");
        return;
    }
    $self->hipchat->api->universal_req(
        GET => $self->capabilities_url,
        sub {
            my ($ok, $data, $err) = @_;
            if (!$ok) {
                $self->log->error("Cannot get capabilities_document ($self): $err");
            } else {
                $self->_add_cap_doc($data);
                $self->issue_token;
            }
        }
    );
}

1;

=pod

=head1 NAME

AnyEvent::HipChat::Store::Installation - Hipchat room/group connection container.

=head1 SYNOPSIS

    my $data = JSON->new->decode({
        "oauthId": "4c507561-70b2-42d1-9dea-6597acc364b1",
        "capabilitiesUrl": "https://192.168.1.49/v2/capabilities",
        "roomId": 2, "groupId": 1,
        "oauthSecret": "ICWxPk7s8y1yTiBqM3C7gmsX0zNETIWTwPJt3j2v"});

    my $inst = AnyEvent::HipChat::Store::Installation->new(
        hipchat => <AnyEvent::Hipchat >,
        data => $data
    ));

    $inst->get_capabilities_document();

=head1 DESCRIPTION

Contain hipchat connection information such as:
oauthId, capabilitiesUrl, roomId, groupId, oauthSecret,
capabilities document, access token

Emit 'ready' event then token issued

=head1 METHODS

=head2 new(%args)

Make new installation

=head2 ready

Emit ready event, with $self as first argument

=head2 get_capabilities_document()

Get document from B<capabilities_url>

=head2 next_room_key()

Simple rooms counter, just save int and return next value

=head2 issue_token()

Start issue token procedure

=head2 serrialize, deserrialize

Serrialize/deserrialize L<AnyEvent::HipChat::Store::Installation> as Perl href

=head2 ee()

Get L<AnyEvent::Hipchat::EventEmmiter> instance

=head2 oauth_id(), capabilities_url(), room_id(), group_id(), oauth_secret()

Accessor to relative hipchat data

=head2 token(), api_url(), token_url(), authorization_url()

Various accessors

=head1 SEE ALSO

L<AnyEvent::HipChat>, L<AnyEvent::HipChat::Store>

=cut
