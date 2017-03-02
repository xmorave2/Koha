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

use C4::Auth;
use C4::Output;
use Koha::Database;

my $input = new CGI;

my ($template, $loggedinuser, $cookie) =
    get_template_and_user({template_name => "tools/oai-pmh-harvester/record.tt",
        query => $input,
        type => "intranet",
        authnotrequired => 0,
        flagsrequired => {tools => 'manage_staged_marc'},
    });

my $import_oai_id = $input->param('import_oai_id');
if ($import_oai_id){
    my $schema = Koha::Database->new()->schema();
    if ($schema){
        my $rs = $schema->resultset("OaiHarvesterHistory");
        if ($rs){
            my $row = $rs->find($import_oai_id);
            if ($row){
                my $record = $row->record;
                if ($record){
                    $template->{VARS}->{ record } = $record;
                }
            }
        }
    }
}

output_html_with_http_headers($input, $cookie, $template->output);
