package AnyEvent::HipChat::Utils;

use strict;
use warnings;
use parent q/Exporter/;
use Digest::MD5 qw/md5_hex/;

our @EXPORT    = qw/OK FAILED/;
our @EXPORT_OK = qw/merge_descr OK FAILED make_rnd_str/;

use constant OK     => 1;
use constant FAILED => undef;

sub merge_descr {
    my ($from, $to) = @_;
    for my $k (keys %{$$from}) {
        my $v = $$from->{$k};
        if (ref($v) eq 'HASH') {
            $$to->{$k} = {} if not exists $$to->{$k} or ref($$to->{$k}) ne 'HASH';
            merge_descr(\$v, \$$to->{$k});
        } else {
            $$to->{$k} = $v;
        }
    }
}

sub make_rnd_str {
    md5_hex time . $$ . rand();
}

1;

=pod

=head1 NAME

AnyEvent::HipChat::Utils - utility functions

=head1 DESCRIPTION

Provide various utility functions

=head1 FUNCTIONS

=head2 merge_descr($from, $to)

Merge two hashref, used to install user settings to capability descriptor

=head2 make_rnd_str()

Return random string

=head1 SEE ALSO

L<AnyEvent::HipChat>

=cut
