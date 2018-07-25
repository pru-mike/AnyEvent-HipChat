#!/usr/bin/env perl

use strict;
use warnings;
use feature qw/say/;
use LWP::Simple;
use Web::Query;
use HTML::TableExtract;
use Data::Dumper;
use Try::Tiny;
use YAML;
use Getopt::Std;

my $host = q[https://www.hipchat.com];

our ($opt_s, $opt_h, $opt_m);
getopts("s:m:h");
HELP_MESSAGE() if $opt_h;

$host = $opt_s || $host;

my %spec;
my @m;
if ($opt_m) {
    @m = map { "/docs/apiv2/method/$_" } split /,| /, $opt_m;
} else {
    @m = find_methods($host);
}
my $all = @m;
my $i   = 0;
for (@m) {
    my $url = qq[$host$_];
    $i++;
    if (m{/share_file_}) {
        warn "Skip $url [$i/$all]\n";
        next;
    }
    try {
        my ($k, $v) = get_method_doc($url);
        $spec{$k} = $v;
        warn "Gather $url [$i/$all]\n";
    }
    finally {
        if (@_) {
            warn "Can't get doc [$url]: @_\n";
        }
    };
}

print Dump(\%spec);

sub find_methods {
    my $host = shift;
    my $url  = "$host/docs/apiv2";
    my @methods;
    wq($url)->find('.aui-page-panel-nav')->find('a')->each(
        sub {
            my $href = $_->attr('href');
            push @methods, $href if $href =~ m{/method/};
        }
    );
    return @methods;
}

sub get_method_doc {
    my $url       = shift;
    my $func_name = $url =~ s{.*/}{}r;
    my $q         = wq($url)->find('.aui-page-panel-content');
    my $name      = $q->find('h2')->first->text;
    my $method    = $q->find('.resource-request .resource-verb')->text;
    my $path      = $q->find('.resource-request .resource-path')->text;
    my $descr     = $q->find('.resource-desc')->text;

    my $is_body;
    my $is_pp;
    my @tables;
    my @path_params;
    my @body_params;

    $q->find('h4')->each(
        sub {
            $_->text eq 'Request body'    && $is_body++;
            $_->text eq 'Path parameters' && $is_pp++;
        }
    );
    if ($is_pp or $is_body) {
        $q->find('table')->each(
            sub {
                push @tables, $_->as_html;
            }
        );
    }
    if ($is_pp) {
        shift @tables;
        @path_params = (path_params => [map { s/_or_.*//r } $path =~ m/{(\w+)}/g]);
        $path =~ s/{[^}]+}/%s/g;
    }
    if ($is_body) {
        my $html = shift @tables;
        my $te   = HTML::TableExtract->new(headers => [qw(Type Property Description Required?)]);
        my $t    = $te->parse($html)->first_table_found();
        if ($t) {
            for my $row (@{ $t->rows }) {
                my $param       = $row->[1];
                my $first_level = $row->[1] =~ /^\S/;
                my $required    = $row->[3];
                my $has_default = $row->[2] =~ /Defaults/;
                if ($first_level) {
                    if ($required and !$has_default) {
                        push @body_params, $param;

                        # workaround for something looks like a bug in /create_room_webhook
                        # there is a 'key' field in body, is's marked as not required, but is's required
                    } elsif (
                        $is_pp and !$required and grep {
                            $param eq $_
                        } @{ $path_params[1] }
                      )
                    {
                        push @body_params, $param;
                    }
                }
            }
            @body_params = (body_params => [@body_params]) if @body_params;
        } else {
            warn "Hmmm... Can't parse body table: $html";
        }
    }

    return $func_name => {
        doc_url  => $url,
        method   => $method,
        endpoint => $path,
        @path_params,
        @body_params,
        descr => $descr,
    };
}

sub HELP_MESSAGE {
    my ($n) = $0 =~ m{([^/]+$)};
    print <<"HELP";
    $n - gather hipchat api spec from url

    Usage: $n -s <hipchat server> -h -m <method list> > spec.yaml
      -u hipchat host, default $host (doc url <host>/docs/apiv2)
      -m method list splited by comma or space, generate spec only for
         pointed method
      -h this messsage
HELP
    exit;
}
