# Copyright (C) 2015-2016 SUSE LLC
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

BEGIN {
    unshift @INC, 'lib';
}

use Mojo::Base -strict;
use Test::More;
use Test::Mojo;
use Test::Warnings;
use OpenQA::Test::Case;
use Data::Dumper;
use IO::Socket::INET;

# optional but very useful
eval 'use Test::More::Color';
eval 'use Test::More::Color "foreground"';

use File::Path qw/make_path remove_tree/;
use Module::Load::Conditional qw/can_load/;

my $test_case = OpenQA::Test::Case->new;
$test_case->init_data;

use t::ui::PhantomTest;

# skip if phantomjs or Selenium::Remote::WDKeys isn't available
my $driver = t::ui::PhantomTest::call_phantom();
unless ($driver && can_load(modules => {'Selenium::Remote::WDKeys' => undef,})) {
    plan skip_all => 'Install phantomjs, Selenium::Remote::Driver, and Selenium::Remote::WDKeys to run these tests';
    exit(0);
}

is($driver->get_title(), "openQA", "on main page");
is($driver->find_element('#user-action', 'css')->get_text(), 'Login', "noone logged in");
$driver->find_element('Login', 'link_text')->click();
# we're back on the main page
is($driver->get_title(), "openQA", "back on main page");
# but ...

is($driver->find_element('#user-action', 'css')->get_text(), 'Logged in as Demo', "logged in as demo");

# expand user menu
$driver->find_element('#user-action a', 'css')->click();
like($driver->find_element('#user-action', 'css')->get_text(), qr/Operators Menu/,      'demo is operator');
like($driver->find_element('#user-action', 'css')->get_text(), qr/Administrators Menu/, 'demo is admin');

# Demo is admin, so go there
$driver->find_element('Workers', 'link_text')->click();

is($driver->get_title(), "openQA: Workers", "on workers overview");

subtest 'add product' => sub() {
    # go to product first
    $driver->find_element('#user-action a', 'css')->click();
    $driver->find_element('Medium types',   'link_text')->click();

    is($driver->get_title(), "openQA: Medium types", "on products");
    t::ui::PhantomTest::wait_for_ajax;
    my $elem = $driver->find_element('.admintable thead tr', 'css');
    my @headers = $driver->find_child_elements($elem, 'th');
    is(@headers, 6, "6 columns");

    # the headers are specific to our fixtures - if they change, we have to adapt
    is((shift @headers)->get_text(), "Distri",   "1st column");
    is((shift @headers)->get_text(), "Version",  "2nd column");
    is((shift @headers)->get_text(), "Flavor",   "3rd column");
    is((shift @headers)->get_text(), "Arch",     "4th column");
    is((shift @headers)->get_text(), "Settings", "5th column");
    is((shift @headers)->get_text(), "Actions",  "6th column");

    # now check one row by example
    $elem = $driver->find_element('.admintable tbody tr:nth-child(1)', 'css');
    @headers = $driver->find_child_elements($elem, 'td');

    # the headers are specific to our fixtures - if they change, we have to adapt
    is((shift @headers)->get_text(), "opensuse", "distri");
    is((shift @headers)->get_text(), "13.1",     "version");
    is((shift @headers)->get_text(), "DVD",      "flavor");
    is((shift @headers)->get_text(), "i586",     "arch");

    is(@{$driver->find_elements('//button[@title="Edit"]')}, 1, "1 edit button before");

    is($driver->find_element('//input[@value="New medium"]')->click(), 1, 'new medium');

    $elem = $driver->find_element('.admintable tbody tr:last-child', 'css');
    is($elem->get_text(), '', 'new row empty');
    my @fields = $driver->find_child_elements($elem, '//input[@type="text"]');
    is(@fields, 4, '4 input fields');
    (shift @fields)->send_keys('sle');      # distri
    (shift @fields)->send_keys('13');       # version
    (shift @fields)->send_keys('DVD');      # flavor
    (shift @fields)->send_keys('arm19');    # arch
    is(scalar @{$driver->find_child_elements($elem, '//textarea')}, 1, '1 textarea');

    is($driver->find_element('//button[@title="Add"]')->click(), 1, 'added');
    t::ui::PhantomTest::wait_for_ajax;
    is(@{$driver->find_elements('//button[@title="Edit"]')}, 2, "2 edit buttons afterwards");

    # check the distri name will be lowercase after added a new one
    is($driver->find_element('//input[@value="New medium"]')->click(), 1, 'new medium');

    $elem = $driver->find_element('.admintable tbody tr:last-child', 'css');
    is($elem->get_text(), '', 'new row empty');
    @fields = $driver->find_child_elements($elem, '//input[@type="text"]');
    is(@fields, 4, '4 input fields');
    (shift @fields)->send_keys('OpeNSusE');    # distri name has capital letter and many upper/lower case combined
    (shift @fields)->send_keys('13.2');        # version
    (shift @fields)->send_keys('DVD');         # flavor
    (shift @fields)->send_keys('ppc64le');     # arch
    @fields = $driver->find_child_elements($elem, '//textarea');
    is(@fields, 1, '1 textarea');
    (shift @fields)->send_keys("DVD=2\nIOS_MAXSIZE=4700372992");

    is($driver->find_element('//button[@title="Add"]')->click(), 1, 'added');
    t::ui::PhantomTest::wait_for_ajax;
    is(@{$driver->find_elements('//button[@title="Edit"]')}, 3, "3 edit buttons afterwards");
};

subtest 'add machine' => sub() {
    # go to machines first
    $driver->find_element('#user-action a', 'css')->click();
    $driver->find_element('Machines',       'link_text')->click();

    is($driver->get_title(), "openQA: Machines", "on machines list");
    t::ui::PhantomTest::wait_for_ajax;
    my $elem = $driver->find_element('.admintable thead tr', 'css');
    my @headers = $driver->find_child_elements($elem, 'th');
    is(@headers, 4, "4 columns");

    # the headers are specific to our fixtures - if they change, we have to adapt
    is((shift @headers)->get_text(), "Name",     "1st column");
    is((shift @headers)->get_text(), "Backend",  "2nd column");
    is((shift @headers)->get_text(), "Settings", "3th column");
    is((shift @headers)->get_text(), "Actions",  "4th column");

    # now check one row by example
    $elem = $driver->find_element('.admintable tbody tr:nth-child(3)', 'css');
    @headers = $driver->find_child_elements($elem, 'td');
    # the headers are specific to our fixtures - if they change, we have to adapt
    is((shift @headers)->get_text(), "Laptop_64",                "name");
    is((shift @headers)->get_text(), "qemu",                     "backend");
    is((shift @headers)->get_text(), "LAPTOP=1\nQEMUCPU=qemu64", "cpu");

    is(@{$driver->find_elements('//button[@title="Edit"]')}, 3, "3 edit buttons before");

    is($driver->find_element('//input[@value="New machine"]')->click(), 1, 'new machine');

    $elem = $driver->find_element('.admintable tbody tr:last-child', 'css');
    is($elem->get_text(), '', 'new row empty');
    my @fields = $driver->find_child_elements($elem, '//input[@type="text"]');
    is(@fields, 2, '2 input fields');
    (shift @fields)->send_keys('HURRA');    # name
    (shift @fields)->send_keys('ipmi');     # backend
    @fields = $driver->find_child_elements($elem, '//textarea');
    is(@fields, 1, '1 textarea');
    (shift @fields)->send_keys("SERIALDEV=ttyS1\nTIMEOUT_SCALE=3\nWORKER_CLASS=64bit-ipmi");    # cpu
    is($driver->find_element('//button[@title="Add"]')->click(), 1, 'added');
    t::ui::PhantomTest::wait_for_ajax;

    is(@{$driver->find_elements('//button[@title="Edit"]')}, 4, "4 edit buttons afterwards");
};

subtest 'add test suite' => sub() {
    # go to tests first
    $driver->find_element('#user-action a', 'css')->click();
    $driver->find_element('Test suites',    'link_text')->click();

    is($driver->get_title(), "openQA: Test suites", "on test suites");
    t::ui::PhantomTest::wait_for_ajax;
    my $elem = $driver->find_element('.admintable thead tr', 'css');
    my @headers = $driver->find_child_elements($elem, 'th');
    is(@headers, 3, "3 columns");

    # the headers are specific to our fixtures - if they change, we have to adapt
    is((shift @headers)->get_text(), "Name",     "1st column");
    is((shift @headers)->get_text(), "Settings", "2th column");
    is((shift @headers)->get_text(), "Actions",  "3th column");

    # now check one row by example
    $elem = $driver->find_element('.admintable tbody tr:nth-child(3)', 'css');
    @headers = $driver->find_child_elements($elem, 'td');

    # the headers are specific to our fixtures - if they change, we have to adapt
    is((shift @headers)->get_text(), "RAID0", "name");
    is((shift @headers)->get_text(), "DESKTOP=kde\nINSTALLONLY=1\nRAIDLEVEL=0", "DESKTOP");

    is(@{$driver->find_elements('//button[@title="Edit"]')}, 7, "7 edit buttons before");

    is($driver->find_element('//input[@value="New test suite"]')->click(), 1, 'new test suite');

    $elem = $driver->find_element('.admintable tbody tr:last-child', 'css');
    is($elem->get_text(), '', 'new row empty');
    my @fields = $driver->find_child_elements($elem, '//input[@type="text"]');
    is(@fields, 1, '1 input field');
    (shift @fields)->send_keys('xfce');    # name
    @fields = $driver->find_child_elements($elem, '//textarea');
    is(@fields, 1, '1 textarea');

    is($driver->find_element('//button[@title="Add"]')->click(), 1, 'added');
    t::ui::PhantomTest::wait_for_ajax;
    is(@{$driver->find_elements('//button[@title="Edit"]')}, 8, "8 edit buttons afterwards");

    # can add entry with single, double quotes, special chars
    my ($suiteName, $suiteKey, $suiteValue) = qw/t"e\\st'Suite\' te\'\\st"Ke"y; te'\""stVa;l%&ue/;

    is($driver->find_element('//input[@value="New test suite"]')->click(), 1, 'new test suite');
    $elem = $driver->find_element('.admintable tbody tr:last-child', 'css');
    is($elem->get_text(), '', 'new row empty');
    my $name     = $driver->find_child_element($elem, '//input[@type="text"]');
    my $settings = $driver->find_child_element($elem, '//textarea');
    $name->send_keys($suiteName);
    $settings->send_keys("$suiteKey=$suiteValue");
    is($driver->find_element('//button[@title="Add"]')->click(), 1, 'added');
    # leave the ajax some time
    t::ui::PhantomTest::wait_for_ajax;
# now read data back and compare to original, name and value shall be the same, key sanitized by removing all special chars
    $elem = $driver->find_element('.admintable tbody tr:last-child', 'css');
    is($elem->get_text(), "$suiteName testKey=$suiteValue", 'stored text is the same except key');
    # try to edit and save
    ok($driver->find_child_element($elem, './td/button[@title="Edit"]')->click(), 'editing enabled');
    t::ui::PhantomTest::wait_for_ajax;

    $elem = $driver->find_element('.admintable tbody tr:last-child', 'css');
    $name     = $driver->find_child_element($elem, './td/input[@type="text"]');
    $settings = $driver->find_child_element($elem, './td/textarea');
    is($name->get_value,    $suiteName,            'suite name edit box match');
    is($settings->get_text, "testKey=$suiteValue", 'textarea matches sanitized key and value');
    ok($driver->find_child_element($elem, '//button[@title="Update"]')->click(), 'editing saved');

    # reread and compare to original
    t::ui::PhantomTest::wait_for_ajax;
    $elem = $driver->find_element('.admintable tbody tr:last-child', 'css');
    is($elem->get_text(), "$suiteName testKey=$suiteValue", 'stored text is the same except key');
};

subtest 'add job group' => sub() {
    # navigate to job groups
    $driver->find_element('#user-action a', 'css')->click();
    $driver->find_element('Job groups',     'link_text')->click();
    is($driver->get_title(), "openQA: Job groups", "on groups");

    # check whether all job groups from fixtures are displayed
    my $list_element = $driver->find_element('#job_group_list', 'css');
    my @parent_group_entries = $driver->find_child_elements($list_element, 'li');
    is((shift @parent_group_entries)->get_text(), 'opensuse',      'first parentless group present');
    is((shift @parent_group_entries)->get_text(), 'opensuse test', 'second parentless group present');
    is(@parent_group_entries,                     0,               'only parentless groups present');

    # disable animations to speed up test
    $driver->execute_script('$(\'#add_group_modal\').removeClass(\'fade\'); jQuery.fx.off = true;');

    # add new parentless group, leave name empty (which should lead to error)
    $driver->find_element('//a[@title="Add new job group on top-level"]')->click();
    $driver->find_element('#create_group_button', 'css')->click();
    t::ui::PhantomTest::wait_for_ajax;
    $list_element = $driver->find_element('#job_group_list', 'css');
    @parent_group_entries = $driver->find_child_elements($list_element, 'li');
    is((shift @parent_group_entries)->get_text(), 'opensuse',      'first parentless group present');
    is((shift @parent_group_entries)->get_text(), 'opensuse test', 'second parentless group present');
    is(@parent_group_entries,                     0,               'and also no more parent groups');
    like(
        $driver->find_element('#new_group_name_group ', 'css')->get_text(),
        qr/The group name must not be empty/,
        'refuse creating group with empty name'
    );

    # add new parentless group (dialog should still be open), this time enter a name
    $driver->find_element('#new_group_name',      'css')->send_keys('Cool Group');
    $driver->find_element('#create_group_button', 'css')->click();
    t::ui::PhantomTest::wait_for_ajax;

    # new group should be present
    $list_element = $driver->find_element('#job_group_list', 'css');
    @parent_group_entries = $driver->find_child_elements($list_element, 'li');
    is((shift @parent_group_entries)->get_text(), 'Cool Group',    'new parentless group present');
    is((shift @parent_group_entries)->get_text(), 'opensuse',      'first parentless group from fixtures present');
    is((shift @parent_group_entries)->get_text(), 'opensuse test', 'second parentless group from fixtures present');
    is(@parent_group_entries,                     0,               'no further grops present');

    # add new parent group
    $driver->find_element('//a[@title="Add new folder"]')->click();
    $driver->find_element('#new_group_name',      'css')->send_keys('New parent group');
    $driver->find_element('#create_group_button', 'css')->click();
    t::ui::PhantomTest::wait_for_ajax;

    # check whether parent is present
    $list_element = $driver->find_element('#job_group_list', 'css');
    @parent_group_entries = $driver->find_child_elements($list_element, 'li');
    is(@parent_group_entries, 4,
        'now 4 top-level groups present (one is new parent, remaining are parentless job groups)');
    my $new_groups_entry = shift @parent_group_entries;
    is($new_groups_entry->get_text(), 'New parent group', 'new group present');

    # test Drag & Drop: done manually

    # reload page to check whether the changes persist
    $driver->find_element('#user-action a', 'css')->click();
    $driver->find_element('Job groups',     'link_text')->click();

    $list_element = $driver->find_element('#job_group_list', 'css');
    @parent_group_entries = $driver->find_child_elements($list_element, 'li');
    is(@parent_group_entries, 4,
        'now 4 top-level groups present (one is new parent, remaining are parentless job groups)');
    is((shift @parent_group_entries)->get_text(), 'Cool Group',       'new parentless group present');
    is((shift @parent_group_entries)->get_text(), 'opensuse',         'first parentless group from fixtures present');
    is((shift @parent_group_entries)->get_text(), 'opensuse test',    'second parentless group from fixtures present');
    is((shift @parent_group_entries)->get_text(), 'New parent group', 'new group present');
};

subtest 'job property editor' => sub() {
    is($driver->get_title(), 'openQA: Job groups', 'on job groups');

    # navigate to editor first
    $driver->find_element('Cool Group',                    'link')->click();
    $driver->find_element('#job-group-name + form button', 'css')->click();

    subtest 'current/default values present' => sub() {
        is($driver->find_element('#editor-name',              'css')->get_value(), 'Cool Group', 'name');
        is($driver->find_element('#editor-size-limit',        'css')->get_value(), '100',        'size limit');
        is($driver->find_element('#editor-keep-logs-in-days', 'css')->get_value(), '30',         'keep logs in days');
        is($driver->find_element('#editor-keep-important-logs-in-days', 'css')->get_value(),
            '120', 'keep important logs in days');
        is($driver->find_element('#editor-keep-results-in-days', 'css')->get_value(), '365', 'keep results in days');
        is($driver->find_element('#editor-keep-important-results-in-days', 'css')->get_value(),
            '0', 'keep important results in days');
        is($driver->find_element('#editor-default-priority', 'css')->get_value(), '50', 'default priority');
        is($driver->find_element('#editor-description',      'css')->get_value(), '',   'no description yet');
    };

    subtest 'edit some properties' => sub() {
        # those keys will be appended
        $driver->find_element('#editor-name',                           'css')->send_keys(' has been edited!');
        $driver->find_element('#editor-size-limit',                     'css')->send_keys('0');
        $driver->find_element('#editor-keep-important-results-in-days', 'css')->send_keys('500');
        $driver->find_element('#editor-description',                    'css')->send_keys('Test group');
        $driver->find_element('p.buttons button.btn-primary',           'css')->click();
        # ensure there is no race condition, even though the page is reloaded
        t::ui::PhantomTest::wait_for_ajax;

        # now reload the page to see if we succeeded
        $driver->get($driver->get_current_url());
        is($driver->get_title(), 'openQA: Jobs for Cool Group has been edited!', 'new name on title');
        $driver->find_element('#job-group-name + form button', 'css')->click();
        is($driver->find_element('#editor-name', 'css')->get_value(), 'Cool Group has been edited!', 'name edited');
        is($driver->find_element('#editor-size-limit', 'css')->get_value(), '1000', 'size edited');
        is($driver->find_element('#editor-keep-important-results-in-days', 'css')->get_value(),
            '500', 'keep important results in days edited');
        is($driver->find_element('#editor-default-priority', 'css')->get_value(),
            '50', 'default priority should be the same');
        is($driver->find_element('#editor-description', 'css')->get_value(), 'Test group', 'description added');
    };
};

subtest 'edit mediums' => sub() {
    is($driver->get_title(), 'openQA: Jobs for Cool Group has been edited!', 'on jobs for Cool Test has been edited!');

    t::ui::PhantomTest::wait_for_ajax;
    $driver->find_element('Test new medium as part of this group', 'link')->click();

    my $select = $driver->find_element('#medium', 'css');
    my $option = $driver->find_child_element($select, './option[contains(text(), "sle-13-DVD-arm19")]');
    $option->click();
    $select = $driver->find_element('#machine', 'css');
    $option = $driver->find_child_element($select, './option[contains(text(), "HURRA")]');
    $option->click();
    $select = $driver->find_element('#test', 'css');
    $option = $driver->find_child_element($select, './option[contains(text(), "xfce")]');
    $option->click();

    $driver->find_element('//input[@type="submit"]')->submit();

    is($driver->get_title(), 'openQA: Jobs for Cool Group has been edited!', 'on job groups');
    t::ui::PhantomTest::wait_for_ajax;

    my $td = $driver->find_element('#sle_13_DVD_arm19_xfce_chosen .search-field', 'css');
    is('', $td->get_text(), 'field is empty for product 2');
    $driver->mouse_move_to_location(element => $td);
    $driver->button_down();
    t::ui::PhantomTest::wait_for_ajax;

    $driver->send_keys_to_active_element('64bit');
    # as we load this at runtime rather than `use`ing it, we have to
    # access it explicitly like this
    $driver->send_keys_to_active_element(Selenium::Remote::WDKeys->KEYS->{'enter'});

    # now reload the page to see if we succeeded
    $driver->find_element('#user-action a', 'css')->click();
    $driver->find_element('Job groups',     'link_text')->click();

    is($driver->get_title(), 'openQA: Job groups', 'on groups');
    $driver->find_element('Cool Group has been edited!', 'link')->click();

    my @picks = $driver->find_elements('.search-choice', 'css');
    is((shift @picks)->get_text(), '64bit', 'found one');
    is((shift @picks)->get_text(), 'HURRA', 'found two');
    is_deeply(\@picks, [], 'found no three');

    # briefly check the asset list
    $driver->find_element('#user-action a', 'css')->click();
    $driver->find_element('Assets',         'link_text')->click();
    is($driver->get_title(), "openQA: Assets", "on asset");
    t::ui::PhantomTest::wait_for_ajax;

    $td = $driver->find_element('tr#asset_1 td.t_created', 'css');
    is('about 2 hours ago', $td->get_text(), 'timeago 2h');
};

t::ui::PhantomTest::kill_phantom();
done_testing();
