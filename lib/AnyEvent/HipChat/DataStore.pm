package AnyEvent::HipChat::DataStore;

use strict;

sub new {
    bless {}, shift;
}

sub load { }

sub save { }

1;

=pod

=head1 NAME

AnyEvent::HipChat::DataStore - Installation storage interface class

=head1 DESCRIPTION

Provide interface and stub realization for installation storage

=head1 SEE ALSO

L<AnyEvent::HipChat>, L<AnyEvent::HipChat::DataStore::File>, L<AnyEvent::HipChat::Store::Installation>

=cut
