#!/usr/bin/perl

# Copyright 2017 Prosentient Systems
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# Koha is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with Koha; if not, see <http://www.gnu.org/licenses>.

use Modern::Perl;
use UUID;

use C4::Auth;
use C4::Output;
use Koha::OAI::Harvester::Requests;
use Koha::BiblioFrameworks;
use Koha::Database;

my $input = new CGI;

my ($template, $loggedinuser, $cookie) =
    get_template_and_user({template_name => "tools/oai-pmh-harvester/request.tt",
        query => $input,
        type => "intranet",
        authnotrequired => 0,
        flagsrequired => {tools => 'manage_staged_marc'},
    });

my $op = $input->param('op');
my $id = $input->param('id');

my @frameworks = Koha::BiblioFrameworks->as_list();
$template->{VARS}->{ frameworks } = \@frameworks;

my $schema = Koha::Database->new()->schema();
my $rs = $schema->resultset("MarcMatcher");
my @matchers = $rs->all;
$template->{VARS}->{ matchers } = \@matchers;

my $http_url = $input->param('http_url');
my $http_username = $input->param('http_username');
my $http_password = $input->param('http_password');
my $http_realm = $input->param('http_realm');

my $oai_verb = $input->param('oai_verb');
my $oai_metadataPrefix = $input->param('oai_metadataPrefix');
my $oai_identifier = $input->param('oai_identifier');
my $oai_from = $input->param('oai_from');
my $oai_until = $input->param('oai_until');
my $oai_set = $input->param('oai_set');

my $import_filter = $input->param('import_filter') // 'default';
my $import_framework_code = $input->param('import_framework_code');
my $import_record_type = $input->param('import_record_type');
my $import_matcher_code = $input->param('import_matcher_code');

my $interval = $input->param("interval") ? int ( $input->param("interval") ) : 0;
my $name = $input->param("name");

my $save = $input->param('save');
my $test_parameters = $input->param('test_parameters');

my $request = $id ? Koha::OAI::Harvester::Requests->find($id) : Koha::OAI::Harvester::Request->new();
if ($request){
    if ($op eq "create" || $op eq "update"){
        $request->set({
            name => $name,
            http_url => $http_url,
            http_username => $http_username,
            http_password => $http_password,
            http_realm => $http_realm,
            oai_verb => $oai_verb,
            oai_metadataPrefix => $oai_metadataPrefix,
            oai_identifier => $oai_identifier,
            oai_from => $oai_from,
            oai_until => $oai_until,
            oai_set => $oai_set,
            import_filter => $import_filter,
            import_framework_code => $import_framework_code,
            import_record_type => $import_record_type,
            import_matcher_code => $import_matcher_code,
            interval => $interval,
        });
    }
}

if ($test_parameters){
    my $errors = $request->validate();
    $template->{VARS}->{ errors } = $errors;
    $template->{VARS}->{ test_parameters } = 1;
}

if ($op eq "new"){
    #Empty form with some defaults
    $request->import_filter("default") unless $request->import_filter;
    $request->interval(0) unless $request->interval;
}
elsif ($op eq "create"){
    if ($save){
        my ($uuid,$uuid_string);
        UUID::generate($uuid);
        UUID::unparse($uuid, $uuid_string);
        $request->uuid($uuid_string);
        $request->store;
        print $input->redirect('/cgi-bin/koha/tools/oai-pmh-harvester/dashboard.pl#saved_results');
        exit;
    }
}
elsif ( $op eq "edit"){
    $template->{VARS}->{ id } = $id;
}
elsif ($op eq "update"){
    $template->{VARS}->{ id } = $id;
    if ($save){
        $request->store;
        print $input->redirect('/cgi-bin/koha/tools/oai-pmh-harvester/dashboard.pl#saved_results');
        exit;
    }
}
elsif ($op eq "delete"){
    if ($request){
        $request->delete;
        print $input->redirect('/cgi-bin/koha/tools/oai-pmh-harvester/dashboard.pl#saved_results');
    }
}
else {
    print $input->redirect('/cgi-bin/koha/tools/oai-pmh-harvester/dashboard.pl#saved_results');
}
$template->{VARS}->{ op } = $op;
$template->{VARS}->{ oai_pmh_request } = $request;

output_html_with_http_headers($input, $cookie, $template->output);
