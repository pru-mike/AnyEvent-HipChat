#!/usr/bin/env perl
use strict;
use warnings;
use autodie;
use FindBin qw/$Bin/;
use lib qq{$Bin/../lib};
use AnyEvent::HipChat::Utils;
use AnyEvent::HipChat;
use YAML q/LoadFile/;
use Getopt::Std;
use Data::Dumper;
use List::Util qw/uniq/;

our ($opt_f);
our $PACKAGE_NAME = q[AnyEvent::HipChat::Api::InjectMethods];
getopts("f:") or HELP_MESSAGE();
HELP_MESSAGE() unless $opt_f and -f $opt_f;

our $API = LoadFile($opt_f);

die "Couldn't find AnyEvent::HipChat" if not exists $INC{'AnyEvent/HipChat.pm'};

my $api_path = $INC{'AnyEvent/HipChat.pm'} =~ s{HipChat\.pm$}{HipChat/Api/InjectMethods.pm}r;
my $api_dir  = $api_path =~ s{InjectMethods.pm}{}r;

die "$api_dir does not exists" unless -d $api_dir;

close STDOUT;
open STDOUT, ">", $api_path;

print <<END;
package $PACKAGE_NAME;

# **************** ! W A R N I N G ! ************************ #
#  This class is AUTOGENERATED.                               #
#  DO NOT modify it by hand.                                  #
#  You should subclass or modify generate_api.pl if needed.   #
# *********************************************************** #

use strict;
use warnings;
use AnyEvent::HipChat::Utils qw/OK FAILED/;
use parent q/Exporter/;

@{[_make_api_methods($API)]}

1;

=pod

=head1 NAME

$PACKAGE_NAME - hipchat api methods implementation

=head1 DESCRIPTION

This class contains hipchat method implementaions.

=head1 LIMITATIONS

This class is B<autogenerated>. Don't modify it by hand.
See B<generate.pl> for details.

=head2 METHODS

@{[_make_api_doc($API)]}

=head1 SEE ALSO

L<AnyEvent::HipChat::Api>, L<AnyEvent::HipChat>

=cut

END

close STDOUT;

sub _make_api_doc {
    my $API = shift;
    my @doc;
    for my $sub (sort keys %$API) {
        my $pp = $API->{$sub}{path_params} || [];
        my $bp = $API->{$sub}{body_params} || [];
        my $ep = $API->{$sub}{endpoint};
        $ep =~ s/(%s)/"<" . shift(@$pp) . ">"/ge;
        my $m     = $API->{$sub}{method};
        my $descr = $API->{$sub}{descr};
        $descr =~ s/(\w)([.:])(?=\w)/$1.\n/g;

        push @doc, "
=item $sub

$m $ep

$descr
";
    }
    return (<<END);

=over

@{[join qq{\n}, @doc]}

=back

END

}

sub _make_api_methods {
    my $API = shift;
    my (@methods, @methods_body);
    for my $sub (sort keys %$API) {
        my $pp = $API->{$sub}{path_params} || [];
        my $bp = $API->{$sub}{body_params} || [];
        my $ep = $API->{$sub}{endpoint};
        my $m  = $API->{$sub}{method};
        my %m_args = (
            $m eq 'GET'
            ? (query_str => '\%args', body => 'undef')
            : (query_str => 'undef', body => '\%args')
        );
        my $checks = join "\n    ",
          map { "do { \$cb->(FAILED, undef, '$_ not defined'), return } if not exists \$args{$_};" }
          uniq(@{$pp}, @{$bp});
        my $path_p = join ', ', map {
            my $p = $_;
            (!grep($_ eq $p, @{$bp}) ? "delete " : "") . "\$args{$p}"
        } @{$pp};
        $path_p = ", $path_p" if ($path_p);

        my $meth = "
sub $sub {
    my \$cb = pop;
    my (\$self, %args) = \@_;
    $checks
    \$self->universal_req(
        $m => sprintf(
            \"$ep\"$path_p
        ),
        $m_args{query_str},
        $m_args{body},
        \$cb
    );
};
        ";
        eval "$meth;1" or die "Cannot create method $sub: $@";
        push @methods,      $sub;
        push @methods_body, $meth;
    }
    my $i = 0;
    return ("our \@EXPORT = qw/", map { $i++; $i % 4 == 0 ? "$_\n" : "$_" } @methods, "/;\n\n", @methods_body);
}

sub HELP_MESSAGE {
    my ($n) = $0 =~ m{([^/]+$)};
    print <<"HELP";
    $n - generate hipchat api method be spec

    Usage: $n -f <spec.yaml>
HELP
    exit;
}
