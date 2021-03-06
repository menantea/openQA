# Copyright (C) 2016 SUSE LLC
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

# see also t/ui/14-dashboard.t for PhantomJS test

BEGIN {
    unshift @INC, 'lib';
}

use Mojo::Base -strict;
use Test::More;
use Test::Mojo;
use Test::Warnings;
use OpenQA::Test::Case;
use JSON qw/decode_json/;

# init test case
my $test_case = OpenQA::Test::Case->new;
$test_case->init_data;
my $t = Test::Mojo->new('OpenQA::WebAPI');
my $auth = {'X-CSRF-Token' => $t->ua->get('/tests')->res->dom->at('meta[name=csrf-token]')->attr('content')};
$test_case->login($t, 'percival');
my $job_groups    = $t->app->db->resultset('JobGroups');
my $parent_groups = $t->app->db->resultset('JobGroupParents');

# regular job groups shown
my $get = $t->get_ok('/')->status_is(200);
my @h2  = $get->tx->res->dom->find('h2 a')->map('text')->each;
is_deeply(\@h2, ['opensuse', 'opensuse test'], 'two groups shown (from fixtures)');

# create (initially) empty parent group
my $test_parent = $parent_groups->create({name => 'Test parent', sort_order => 2});

$get = $t->get_ok('/')->status_is(200);
@h2  = $get->tx->res->dom->find('h2 a')->map('text')->each;
is_deeply(\@h2, ['opensuse', 'opensuse test'], 'empty parent group not shown');

# move opensue group to new parent group
my $opensuse_group = $job_groups->find({name => 'opensuse'});
$opensuse_group->update({parent_id => $test_parent->id});

$get = $t->get_ok('/')->status_is(200);
@h2  = $get->tx->res->dom->find('h2 a')->map('text')->each;
is_deeply(\@h2, ['opensuse test', 'Test parent'], 'parent group shown and opensuse is no more on top-level');

my @h4 = $get->tx->res->dom->find('div.children-collapsed h4 a')->map('text')->each;
is_deeply(\@h4, ['Build0092', 'Build0048@0815', 'Build0048'], 'builds on parent-level shown');
@h4 = $get->tx->res->dom->find('div.collapse h4 a')->map('text')->each;
is_deeply(\@h4, ['opensuse', 'opensuse', 'opensuse'], 'opensuse now shown as child group (for each build)');

# check build limit
$get = $t->get_ok('/?limit_builds=2')->status_is(200);
@h4  = $get->tx->res->dom->find('div.children-collapsed h4 a')->map('text')->each;
is_deeply(\@h4, ['Build0092', 'Build0048'], 'builds on parent-level shown (limit builds)');
@h4 = $get->tx->res->dom->find('div.collapse h4 a')->map('text')->each;
is_deeply(\@h4, ['opensuse', 'opensuse'], 'opensuse now shown as child group (limit builds)');

# also add opensuse test to parent to actually check the grouping
my $opensuse_test_group = $job_groups->find({name => 'opensuse test'});
$opensuse_test_group->update({parent_id => $test_parent->id});

$get = $t->get_ok('/?limit_builds=20&show_tags=1')->status_is(200);
@h2  = $get->tx->res->dom->find('h2 a')->map('text')->each;
is_deeply(\@h2, ['Test parent'], 'only parent shown, no more top-level job groups');

sub check_test_parent {
    my ($default_expanded) = @_;

    @h4 = $get->tx->res->dom->find("div.children-$default_expanded h4 a")->map('text')->each;
    is_deeply(
        \@h4,
        ['Build87.5011', 'Build0092', 'Build0091', 'Build0048@0815', 'Build0048'],
        'builds on parent-level shown'
    );

    my @progress_bars
      = $get->tx->res->dom->find("div.children-$default_expanded .progress")->map('attr', 'title')->each;
    is_deeply(
        \@progress_bars,
        [
            "failed: 1\ntotal: 1",
            "passed: 1\ntotal: 1",
            "passed: 2\nunfinished: 3\nskipped: 1\ntotal: 6",
            "failed: 1\ntotal: 1",
            "softfailed: 2\nfailed: 1\ntotal: 3",
        ],
        'parent-level progress bars are accumulated'
    );

    @h4 = $get->tx->res->dom->find('div#group' . $test_parent->id . '_build0091 h4 a')->map('text')->each;
    is_deeply(\@h4, ['opensuse', 'opensuse test'], 'both child groups shown under common build');
    @progress_bars
      = $get->tx->res->dom->find('div#group' . $test_parent->id . '_build0091 .progress')->map('attr', 'title')->each;
    is_deeply(
        \@progress_bars,
        ["passed: 2\nunfinished: 2\nskipped: 1\ntotal: 5", "unfinished: 1\ntotal: 1"],
        'progress bars for child groups shown correctly'
    );

    is($get->tx->res->dom->find("div.children-$default_expanded .review-all-passed")->size,
        1, 'badge shown on parent-level');

    is($get->tx->res->dom->find("div.children-$default_expanded h4 span i.tag")->size, 0, 'no tags shown yet');
}
check_test_parent('collapsed');

# links are correct
my @urls = $get->tx->res->dom->find('h2 a, .row a')->map('attr', 'href')->each;
for my $url (@urls) {
    next if ($url =~ /^#/);
    $get = $t->get_ok($url)->status_is(200);
}

# parent group overview
$get = $t->get_ok('/parent_group_overview/' . $test_parent->id)->status_is(200);
check_test_parent('expanded');

# add tags (99901 is user ID of arthur)
$opensuse_group->comments->create({text => 'tag:0092:important:some_tag', user_id => 99901});

$get = $t->get_ok('/?limit_builds=20&show_tags=1')->status_is(200);
my @tags = $get->tx->res->dom->find('div.children-collapsed h4 span i.tag')->map('text')->each;
is_deeply(\@tags, ['some_tag'], 'tag is shown on parent-level');

$get  = $t->get_ok('/parent_group_overview/' . $test_parent->id . '?limit_builds=20&show_tags=1')->status_is(200);
@tags = $get->tx->res->dom->find('div.children-expanded h4 span i.tag')->map('text')->each;
is_deeply(\@tags, ['some_tag'], 'tag is shown on parent-level');

done_testing;
