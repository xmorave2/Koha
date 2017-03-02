package Koha::OAI::Harvester::Worker::Download::Stream;

# Copyright Prosentient Systems 2017
#
# This file is part of Koha.
#
# Koha is free software; you can redistribute it and/or modify it under the
# terms of the GNU General Public License as published by the Free Software
# Foundation; either version 3 of the License, or (at your option) any later
# version.
#
# Koha is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE.  See the GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with Koha; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

use Modern::Perl;
use LWP::UserAgent;
use UUID;
use POE;
use JSON;
use File::Path qw/make_path/;

use C4::Context;
use Koha::OAI::Harvester::Downloader;
use parent 'Koha::OAI::Harvester::Worker';

sub new {
    my ($class, $args) = @_;
    $args = {} unless defined $args;
    $args->{type} = "download" unless $args->{type};
    return bless ($args, $class);
}

sub on_start {
    my ($self, $kernel, $heap, $postback,$task,$session) = @_[OBJECT, KERNEL, HEAP, ARG0,ARG1,SESSION];
    #Save postback into heap so other event handlers can use it
    $heap->{postback} = $postback;

    my $task_uuid = $task->{uuid};

    $kernel->sig("cancel" => "stop_worker");
    $kernel->call("harvester","register",$self->{type},$task->{uuid});

    my $child = POE::Wheel::Run->new(
        ProgramArgs => [$task],
        Program => sub {
            my ($args) = @_;
            $self->do_work($args);
        },
        StdoutEvent  => "got_child_stdout",
        StderrEvent  => "got_child_stderr",
        CloseEvent   => "got_child_close",
        NoSetPgrp => 1, #Keep child processes in same group as parent. This is especially useful when using Ctrl+C to kill the whole group.
    );

     $_[KERNEL]->sig_child($child->PID, "got_child_signal");

    # Wheel events include the wheel's ID.
    $_[HEAP]{children_by_wid}{$child->ID} = $child;

    # Signal events include the process ID.
    $_[HEAP]{children_by_pid}{$child->PID} = $child;

    my $logger = $self->{logger};
    if ($logger){
        $logger->debug("Child pid ".$child->PID." started as wheel ".$child->ID);
    }
}

sub do_work {
    my ($self, $task) = @_;
    my $batch = ( $self->{batch} && int($self->{batch}) ) ? $self->{batch} : 100;

    #NOTE: Directory to spool files for processing
    my $spooldir = $task->{spooldir};

    my $task_uuid = $task->{uuid};
    my $task_parameters = $task->{parameters};
    my $interval = $task->{interval};

    my $oai_pmh_parameters = $task_parameters->{oai_pmh};
    my $import_parameters = $task_parameters->{import};

    #NOTE: Overwrite the 'from' and 'until' parameters for repeatable tasks
    if ( $interval && ! $oai_pmh_parameters->{until} ){
        if ($oai_pmh_parameters->{verb} eq "ListRecords"){
            #NOTE: 'effective_from' premiers on the first repetition (ie second request)
            $oai_pmh_parameters->{from} = $task->{effective_from} if $task->{effective_from};
            #NOTE: 'effective_until' appears on the first request
            $oai_pmh_parameters->{until} = $task->{effective_until} if $task->{effective_until};
        }
    }

    my $oai_downloader = Koha::OAI::Harvester::Downloader->new();
    my $url = $oai_downloader->BuildURL($oai_pmh_parameters);

    my $ua = LWP::UserAgent->new();
    #NOTE: setup HTTP Basic Authentication if parameters are supplied
    if($url && $url->host && $url->port){
        my $http_basic_auth = $task_parameters->{http_basic_auth};
        if ($http_basic_auth){
            my $username = $http_basic_auth->{username};
            my $password = $http_basic_auth->{password};
            my $realm = $http_basic_auth->{realm};
            $ua->credentials($url->host.":".$url->port, $realm, $username, $password);
        }
    }

    #NOTE: Prepare database statement handle
    my $dbh = C4::Context->dbh;
    my $sql = "insert into oai_harvester_import_queue (uuid,result) VALUES (?,?)";
    my $sth = $dbh->prepare($sql);

    if($url && $ua){
        #NOTE: You could define the callbacks as object methods instead... that might be nicer...
        #although I suppose it might be a much of a muchness.
        eval {
            my @filename_cache = ();

            $oai_downloader->harvest({
                user_agent => $ua,
                url => $url,
                callback => sub {
                    my ($args) = @_;

                    my $repository = $args->{repository};
                    my $document = $args->{document};

                    #If the spooldir has disappeared, re-create it.
                    if ( ! -d $spooldir ){
                        my $made_spool_directory = make_path($spooldir);
                    }
                    my ($uuid,$uuid_string);
                    UUID::generate($uuid);
                    UUID::unparse($uuid, $uuid_string);
                    my $file_uuid = $uuid_string;
                    my $filename = "$spooldir/$file_uuid";
                    my $state = $document->toFile($filename, 2);
                    if ($state){
                        push(@filename_cache,$filename);
                    }

                    if(scalar @filename_cache == $batch){
                        my $result = {
                            repository => $repository,
                            filenames => \@filename_cache,
                            filter => $import_parameters->{filter},
                            matcher_code => $import_parameters->{matcher_code},
                            frameworkcode => $import_parameters->{frameworkcode},
                            record_type => $import_parameters->{record_type},
                        };
                        eval {
                            my $json_result = to_json($result, { pretty => 1 });
                            $sth->execute($task_uuid,$json_result);
                        };
                        @filename_cache = ();
                    }
                },
                complete_callback => sub {
                    my ($args) = @_;
                    my $repository = $args->{repository};
                    if (@filename_cache){
                        my $result = {
                            repository => "$repository",
                            filenames => \@filename_cache,
                            filter => $import_parameters->{filter},
                            matcher_code => $import_parameters->{matcher_code},
                            frameworkcode => $import_parameters->{frameworkcode},
                            record_type => $import_parameters->{record_type},
                        };
                        eval {
                            my $json_result = to_json($result, { pretty => 1 });
                            $sth->execute($task_uuid,$json_result);
                        };
                    }

                },
            });
        };
        if ($@){
            die "Error during OAI-PMH download";
        }
    }
}

1;
