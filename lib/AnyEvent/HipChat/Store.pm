package AnyEvent::HipChat::Store;

use strict;
use warnings;

use Scalar::Util qw/weaken/;
use parent qw/AnyEvent::HipChat::Base/;

use AnyEvent::HipChat::Store::Installation;

use Class::Accessor::Fast q/moose-like/;

has data_storage => (is => 'ro');
has hipchat => (is => 'ro', isa => 'AnyEvent::HipChat');

sub new {
    my $class = shift;
    my %args  = @_;
    my $self  = {
        store        => {},
        hipchat      => $args{hipchat},
        data_storage => $args{data_storage},
    };
    weaken($self->{hipchat});
    (bless $self, $class)->_init();
}

sub issue_token {
    my $self = shift;
    for my $o (values %{ $self->{store} }) {
        $o->issue_token;
    }
}

sub load {
    my $self = shift;
    my %args = @_;
    my $data = $self->data_storage->load();
    unless ($data) {
        $self->log->info("Nothing to load");
        return;
    }
    my $objects_data = $self->decode_json($data);
    my @objects;
    for my $data (@$objects_data) {
        my $o = AnyEvent::HipChat::Store::Installation->deserrialize($data, hipchat => $self->hipchat,);
        push @objects, $o;
        $self->_add_inst($o->oauth_id, $o);
    }
    return 1;
}

sub save {
    my $self = shift;
    my @store;
    for my $oauth_id (keys %{ $self->{store} }) {
        my $o = $self->{store}{$oauth_id};
        push @store, $o->serrialize;
    }
    $self->data_storage->save($self->encode_json(\@store));
}

sub new_installation {
    my $self = shift;
    my %args = @_;

    #{"oauthId": "4c507561-70b2-42d1-9dea-6597acc364b1",
    #  "capabilitiesUrl": "https://192.168.1.49/v2/capabilities",
    # "roomId": 2, "groupId": 1,
    #  "oauthSecret": "ICWxPk7s8y1yTiBqM3C7gmsX0zNETIWTwPJt3j2v"}
    $self->_add_inst(
        $args{data}->{oauthId},
        AnyEvent::HipChat::Store::Installation->new(
            hipchat => $self->hipchat,
            %args,
        )
    );
}

sub _add_inst {
    my $self = shift;
    my ($oauth_id, $inst_obj) = @_;
    $self->{store}{$oauth_id} = $inst_obj;
}

sub uninstall {
    my $self = shift;
    my $data = shift;
    my $oID  = $data->{oauthId};
    if (exists $self->{store}{$oID}) {
        delete $self->{store}{$oID};
        $self->log->debug("Uninstall $oID from store successful");
    } else {
        $self->log->error("Can't uninstall $oID from store: $oID not found");
    }
}

1;

=pod

=head1 NAME

AnyEvent::HipChat::Store - Installation container

=head1 SYNOPSIS

    $store = AnyEvent::HipChat::Store->new(
        hipchat      => <AnyEvent::HipChat instance>,
        data_storage => AnyEvent::HipChat::DataStore->new(),
    );

   $self->store->new_installation(
       data => <callback_url data>,
   )->get_capabilities_document();

=head1 DESCRIPTION

L<AnyEvent::HipChat::Store::Installation> container.
Contain/save/load/send event to hipchat room/group connection.

=head1 METHODS

=head2 new(%args)

Make new store

=head2 new_installation(%args)

Add new installtion to store

=head2 save()

Save installation to DataStore

=head2 load(%args)

Load installation from DataStore

=head2 uninstall($data)

Delete data from store

=head2 issue_token

Send B<issue_token> to all installation in store

=head1 SEE ALSO

L<AnyEvent::HipChat>, L<AnyEvent::HipChat::Store::Installation>, L<AnyEvent::HipChat::DataStore>

=cut
