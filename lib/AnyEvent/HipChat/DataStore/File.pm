package AnyEvent::HipChat::DataStore::File;

use strict;
use warnings;
use autodie;

sub new {
    my $class = shift;
    my %args  = @_;
    die 'File name not defined' unless $args{file_name};
    bless { fname => $args{file_name} }, $class;
}

sub load {
    my $self = shift;
    return unless -f $self->{fname};
    open my $fh, '<', $self->{fname};
    do {
        local $/ = undef;
        <$fh>;
      }
}

sub save {
    my $self = shift;
    my $data = shift;
    open my $fh, '>', $self->{fname};
    print $fh $data;
}

1;

=pod

=head1 NAME

AnyEvent::HipChat::DataStore::File - Installation storage file realization

=head1 DESCRIPTION

Implement file based L<AnyEvent::HipChat::DataStore>

=head1 METHODS

=head2 new(%args)

  my $hp = AnyEvent::HipChat->new(
    ...
    data_storage  => AnyEvent::HipChat::DataStore::File->new(file_name => $store_file),
    ...
  );

Create DataStore object, that would save B<AnyEvent::HipChat::Store::Installation> to B<>$store_file>

=head1 SEE ALSO

L<AnyEvent::HipChat>, L<AnyEvent::HipChat::DataStore>

=cut
