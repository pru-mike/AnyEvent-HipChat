package AnyEvent::HipChat::EventEmitter;

use strict;
use warnings;
use Carp qw/croak/;

use parent qw/AnyEvent::HipChat::Base/;

my %EVENTS = (
    ready         => [],
    token_updated => [],
);

sub new {
    my $class = shift;
    (bless {}, $class)->_init;
}

sub fire {
    my $self  = shift;
    my $event = shift;
    if (not exists $EVENTS{$event}) {
        $self->log->warnf("event '%s' not defined, available events: %s", $event, join(', ', keys %EVENTS));
    } else {
        $self->log->debugf("Fire '%s' events", $event);
        for (@{ $EVENTS{$event} }) {
            $_->(@_);
        }
    }
}

sub new_event {
    my ($self, $event, $cb) = @_;
    if (not exists $EVENTS{$event} and $event !~ /^user_/) {
        croak sprintf "event '%s' not defined", $event;
    }
    $self->log->debugf("Install new event '%s' handler", $event);
    push @{ $EVENTS{$event} }, $cb;
}

sub new_user_event {
    my ($self, $key, $cb) = @_;
    $self->new_event("user_$key", $cb);
}

sub fire_user_event {
    my $self = shift;
    my $key  = shift;
    $self->fire("user_$key" => @_);
}

1;

=pod

=head1 NAME

AnyEvent::HipChat::EventEmitter - AnyEvent::HipChat event routing

=head1 SYNOPSIS

  my $ee = AnyEvent::HipChat::EventEmitter->new;
  $ee->event_emitter->new_event(ready => sub {...} );
  ...
  #somethere far far away
  $ee->fire(ready => $obj);

=head1 DESCRIPTION

Provide event routing function

=head1 SUPPORTED EVENTS

=head2 ready

=head2 token

=head2 user defined events

=head1 METHODS

=head2 new()

=head2 fire($event)

=head2 new_event($event, $cb)

=head2 new_user_event($key, $cb)

=head2 fire_user_event($key)

=head1 SEE ALSO

L<AnyEvent::HipChat>, L<AnyEvent::HipChat::Api::InjectMethods>,
L<AnyEvent::HipChat::Base>, L<AnyEvent>

=cut
