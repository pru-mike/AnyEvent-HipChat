package AnyEvent::HipChat::Api;

use strict;
use warnings;

use MIME::Base64 qw/encode_base64/;
use Try::Tiny;
use AnyEvent::HTTP ();

use AnyEvent::HipChat ();
use AnyEvent::HipChat::Utils qw/OK FAILED/;
use AnyEvent::HipChat::Api::InjectMethods;

use parent qw/AnyEvent::HipChat::Base/;

use Class::Accessor::Fast q/moose-like/;

has hipchat_host => (is => 'ro', isa => 'Str');
has token        => (is => 'ro', isa => 'Str');

sub new {
    my $class = shift;
    my %args  = @_;

    $args{hipchat_host} =~ s[/$][] if exists $args{hipchat_host} and $args{hipchat_host};

    my $self = {
        hipchat_host => (exists $args{hipchat_host} ? delete $args{hipchat_host} : undef),
        token        => (exists $args{token}        ? delete $args{token}        : undef),
    };
    bless($self, $class)->_init(\%args);
}

sub _init {
    my $self = shift;
    my $args = shift;
    $self->{ua} = (exists $args->{ua} ? delete $args->{ua} : "AnyEvent::HipChat v" . $self->version);
    $self->SUPER::_init($args);
}

sub _make_url {
    my $self         = shift;
    my $endpoint     = shift;
    my $params       = shift;
    my $hipchat_host = "";
    $endpoint !~ /^https?/ && do {
        $hipchat_host = $self->hipchat_host;
        return undef unless $hipchat_host;
    };

    # d'oh
    (($hipchat_host . $endpoint) =~ s{(/v2/v2/)}{/v2/}r)
      . (!keys %$params ? '' : ('?' . join '&', map { "$_=$params->{$_}" } sort keys %$params));
}

sub universal_req {
    my $cb          = pop;
    my $self        = shift;
    my $http_method = shift;
    my $endpoint    = shift;
    my $q           = shift;
    my $body        = shift;

    if ($body) {
        my $ok;
        $body = try {
            $self->encode_json($body);
        }
        finally {
            if (@_) {
                $ok = FAILED;
                $cb->(FAILED, "Cannot encode data to json: @_");
            } else {
                $ok = OK;
            }
        };
        return unless $ok;
    }

    my ($hm, $u) = ($http_method => $self->_make_url($endpoint, $q));
    my $t = $self->token;

    do { $cb->(FAILED, undef, "URL not defined"), return } if not $u;
    AnyEvent::HTTP::http_request $hm => $u,
      body                           => $body,
      headers                        => {
        'accept' => 'application/json; charset=utf-8',
        ($body ? ('content-type' => 'application/json') : ()),
        (
            $t
            ? ('authorization' => 'Bearer ' . $t)
            : ()
        ),
        'user-agent' => $self->{ua},
      },
      sub {
        $self->_process_json_response($cb, $hm, $u, @_);
      }
}

sub _process_json_response {
    my ($self, $cb, $http_method, $url, $data, $hdr) = @_;
    my ($status, $msg, $err);
    try {
        $msg = $self->decode_json($data) if $data;
    }
    finally {
        if (@_) {
            $err    = "Unable to decode incoming message: $data";
            $status = FAILED;
        } else {
            $status = OK;
        }
    };
    if ($hdr->{Status} !~ /^2/) {
        $err    = "$hdr->{Status} $hdr->{Reason}";
        $status = FAILED;
    }
    $self->log->debugf(" <-- %s:%s %d %s %s", $http_method, $url, $hdr->{Status}, $err || "", $data || "");
    $cb->($status, $msg, $err);
}

sub issue_access_token {
    my $cb   = pop;
    my $self = shift;
    my %args = @_;
    $self->_req_access_token(
        cb   => $cb,
        body => "grant_type=client_credentials&scope=" . (join ' ', @{ $args{scopes} }),
        @_,
    );
}

sub refresh_access_token {
    my $cb   = pop;
    my $self = shift;
    my %args = @_;
    $self->_req_access_token(
        cb   => $cb,
        body => "grant_type=refresh_token&refresh_token=$args{token}",
        @_,
    );
}

sub _req_access_token {
    my $self = shift;
    my %args = @_;

    $self->log->debug("body: $args{body}");
    AnyEvent::HTTP::http_request
      POST    => $args{endpoint},
      body    => $args{body},
      headers => {
        authorization  => 'Basic ' . encode_base64(join(':', $args{oauth_id}, $args{oauth_secret}), ''),
        'content-type' => "application/x-www-form-urlencoded",
      },
      sub {
        $self->_process_json_response($args{cb}, 'POST', $args{endpoint}, @_);
      }
}

1;

=pod

=head1 NAME

AnyEvent::HipChat::Api - API client to Atlassian Hipchat

=head1 SYNOPSIS

  use AnyEvent;
  use AnyEvent::HipChat::Api;
  use Log::Any::Adapter ('Stderr', log_level => 'debug' );

  my $api = AnyEvent::HipChat::Api->new(
    hipchat_host => "https://myhipchat.com/",
    token        => "TG9uZyBMaXZlIFBlcmwh",
  );

  my $cv = AnyEvent->condvar;

  $api->send_message(
    room_id => 1,
    message => 'Howdy!',
        sub {
                my ($ok, $data, $err) = @_
                if(!$ok){
                    warn "Can't send message: $err";
                }
                $cv->send;
            }
        }
  );

  $cv->recv;

=head1 DESCRIPTION

Atalssian Hipchat API implementation.
See available methods in L<AnyEvent::HipChat::Api::InjectMethods>

Common usage pattern

  $api = AnyEvent::HipChat::Api->new( ... );
  $api->$some_method(
    %params,
    sub {
       my ($ok, $data, $err) = @_;
       ...
    }
  );

=head1 METHODS

=head2 new(%args)

Constructor, provide following options:

=over

=item hipchat_host

Hipchat server url

=item token

Hipchar access token, it can be user token or add-on token

=item ua

HTTP User-Agent request header, default: AnyEvent::HipChat <VERSION>

=back

=head2 issue_access_token, refresh_access_token

   my @common_params = (
        endpoint     => "https://https://myhipchat.com/v2/oauth/token"
        oauth_id     => ...
        oauth_secret => ...
   );

  $api->issue_access_token(
      scopes => ...
      @common_params
  )

  $api->refres_access_token(
      token => ...
      @common_params
  )

issue_access_token make 'grant_type=client_credentials&scope=<scopes>' request

refres_access_token make 'grant_type=refresh_token&refresh_token=<token>' request

See L<https://developer.atlassian.com/server/hipchat/hipchat-rest-api-access-tokens/> for details

=over

=item endpoint

Usually something like B<"<server url>/v2/oauth/token">

=item oauth_id

OAuth ID

=item oauth_secret

OAuth secret

=item scopes

Array of set of scopes the token should have access to.

=item token

Token refresh to

=back

=head2 hipchat_host

Hipchat server url

=head2 token

Hipchat access token

=head1 SEE ALSO

L<AnyEvent::HipChat>, L<AnyEvent::HipChat::Api::InjectMethods>,
L<AnyEvent::HipChat::Base>, L<AnyEvent>

=cut
