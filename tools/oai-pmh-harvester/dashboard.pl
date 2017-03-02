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
use YAML;

use C4::Auth;
use C4::Context;
use C4::Output;
use Koha::OAI::Harvester::Client;
use Koha::OAI::Harvester::Requests;
use Koha::BiblioFrameworks;
use Koha::Database;

my $context = C4::Context->new();
my $config_filename = $context->{config}->{oai_pmh_harvester_config};
my $client_config = {};
if ($config_filename){
    my $config = YAML::LoadFile($config_filename);
    if ($config && $config->{socket}){
        $client_config->{socket_uri} = $config->{socket};
    }
}

my $input = new CGI;

my ($template, $loggedinuser, $cookie) =
    get_template_and_user({template_name => "tools/oai-pmh-harvester/dashboard.tt",
        query => $input,
        type => "intranet",
        authnotrequired => 0,
        flagsrequired => {tools => 'manage_staged_marc'},
    });

my $op = $input->param('op') // 'list';
my $id = $input->param('id');
my $uuid = $input->param('uuid');

my $client = Koha::OAI::Harvester::Client->new($client_config);
my $is_connected = $client->connect;

if ( ($op eq "send") && $id ){
    if ($is_connected){
        my $request = Koha::OAI::Harvester::Requests->find($id);
        if ($request){
            my $task = {
                name => $request->name,
                uuid => $request->uuid,
                interval => $request->interval,
                parameters => {
                    oai_pmh => {
                        baseURL => $request->http_url,
                        verb => $request->oai_verb,
                        metadataPrefix => $request->oai_metadataPrefix,
                        identifier => $request->oai_identifier,
                        set => $request->oai_set,
                        from => $request->oai_from,
                        until => $request->oai_until,
                    },
                    import => {
                        filter => $request->import_filter,
                        frameworkcode => $request->import_framework_code,
                        matcher_code => $request->import_matcher_code,
                        record_type => $request->import_record_type,
                    },
                },
            };
            if ($request->http_username && $request->http_password && $request->http_realm){
                $task->{parameters}->{http_basic_auth} = {
                    username => $request->http_username,
                    password => $request->http_password,
                    realm => $request->http_realm,
                };
            }
            my $is_created = $client->create($task);
            $template->{VARS}->{ result }->{ send } = $is_created;
        }
    }
}
elsif ( ($op eq "start") && ($uuid) ){
    if ($is_connected){
        my $is_started = $client->start($uuid);
        $template->{VARS}->{ result }->{ start } = $is_started;
    }
}
elsif ( ($op eq "stop") && ($uuid) ){
    if ($is_connected){
        my $is_stopped = $client->stop($uuid);
        $template->{VARS}->{ result }->{ stop } = $is_stopped;
    }
}
elsif ( ($op eq "delete") && ($uuid) ){
    if ($is_connected){
        my $is_deleted = $client->delete($uuid);
        $template->{VARS}->{ result }->{ delete } = $is_deleted;
    }
}

my $requests = Koha::OAI::Harvester::Requests->as_list;
$template->{VARS}->{ saved_requests } = $requests;

my $frameworks = Koha::BiblioFrameworks->as_list();
$template->{VARS}->{ frameworks } = $frameworks;

my $schema = Koha::Database->new()->schema();
my $matcher_rs = $schema->resultset("MarcMatcher");
my @matchers = $matcher_rs->all;
$template->{VARS}->{ matchers } = \@matchers;

if ($is_connected){
    my $submitted_requests = $client->list;
    $template->{VARS}->{ submitted_requests } = $submitted_requests;
}
else {
    $template->{VARS}->{ harvester }->{ offline } = 1;
}

output_html_with_http_headers($input, $cookie, $template->output);