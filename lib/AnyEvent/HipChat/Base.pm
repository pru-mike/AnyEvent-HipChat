package AnyEvent::HipChat::Base;

use strict;
use warnings;

use Carp;
use JSON ();
use Log::Any;
use Class::Accessor::Fast q/moose-like/;

has log => (is => 'ro', isa => 'Log::Any');

sub new {
    my $class = shift;
    croak 'new should be redefined in subclass';
}

sub version {
    $AnyEvent::HipChat::VERSION;
}

sub decode_json {
    my $self = shift;
    $self->{json_decoder}->(@_);
}

sub encode_json {
    my $self = shift;
    $self->{json_encoder}->(@_);
}

sub _init {
    my $self = shift;
    my $args = shift || {};
    $self->{json_decoder} = exists $args->{json_decoder} ? $args->{json_decoder} : \&JSON::decode_json;
    $self->{json_encoder} = exists $args->{json_encoder} ? $args->{json_encoder} : \&JSON::encode_json;
    $self->{log}          = Log::Any->get_logger();
    $self;
}

1;

=pod

=head1 NAME

AnyEvent::HipChat::Base - AnyEvent::HipChat base class

=head1 METHODS

=head2 new()

Abstract method, should be overwrited in descendant

=head2 log()

Retrun Log::Any->get_looger()

=head2 encode_json()

Encode JSON

=head2 decode_json()

Decode JSON

=head2 version()

Return project version

=head1 SEE ALSO

L<AnyEvent::HipChat>

=cut
