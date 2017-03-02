package Koha::OAI::Harvester::Listener;

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
#

use Modern::Perl;
use POE qw(Wheel::SocketFactory Wheel::ReadWrite);
use IO::Socket qw(AF_UNIX);
use JSON;
use URI;

sub new {
    my ($class, $args) = @_;
    $args = {} unless defined $args;
    return bless ($args, $class);
}

sub spawn {
    my ($class, $args) = @_;
    my $self = $class->new($args);
    my $socket = $args->{socket};
    POE::Session->create(
        args => [
            $socket,
        ],
        object_states => [
            $self => {
                _start => "on_start",
                "on_server_success" => "on_server_success",
                "on_server_error" => "on_server_error",
                "on_client_error" => "on_client_error",
                "on_client_input" => "on_client_input",
            },
        ],
    );
}

sub on_start {
    my ($kernel,$heap,$socket_uri) = @_[KERNEL,HEAP,ARG0];

    my $uri = URI->new($socket_uri);
    if ($uri && $uri->scheme eq 'unix'){
        my $socket_path = $uri->path;
        unlink $socket_path if -S $socket_path;
        $heap->{server} = POE::Wheel::SocketFactory->new(
            SocketDomain => AF_UNIX,
            BindAddress => $socket_path,
            SuccessEvent => "on_server_success",
            FailureEvent => "on_server_error",
        );

        #Make the socket writeable to other users like Apache
        chmod 0666, $socket_path;
    }
}

sub on_server_success {
    my ($self, $client_socket, $server_wheel_id, $heap, $session) = @_[OBJECT, ARG0, ARG3, HEAP,SESSION];
    my $logger = $self->{logger};
    my $null_filter = POE::Filter::Line->new(
         Literal => chr(0),
    );
    my $client_wheel = POE::Wheel::ReadWrite->new(
        Handle => $client_socket,
        InputEvent => "on_client_input",
        ErrorEvent => "on_client_error",
        InputFilter => $null_filter,
        OutputFilter => $null_filter,
    );
    $heap->{client}->{ $client_wheel->ID() } = $client_wheel;
    $logger->info("Connection ".$client_wheel->ID()." started.");
    #TODO: Add basic authentication here?
    $client_wheel->put("HELLO");
}

sub on_server_error {
    my ($self, $operation, $errnum, $errstr, $heap, $session) = @_[OBJECT, ARG0, ARG1, ARG2,HEAP, SESSION];
    my $logger = $self->{logger};
    $logger->error("Server $operation error $errnum: $errstr");
    delete $heap->{server};
}

sub on_client_error {
    my ($self, $wheel_id,$heap,$session) = @_[OBJECT, ARG3,HEAP,SESSION];
    my $logger = $self->{logger};
    $logger->info("Connection $wheel_id failed or ended.");
    delete $heap->{client}->{$wheel_id};
}

sub on_client_input {
    my ($self, $input, $wheel_id, $session, $kernel, $heap) = @_[OBJECT, ARG0, ARG1, SESSION, KERNEL, HEAP];
    my $logger = $self->{logger};
    $logger->debug("Server input: $input");
    my $server_response = { msg => "fail"};
    eval {
        my $json_input = from_json($input);
        my $command = $json_input->{command};
        my $body = $json_input->{body};
        if ($command){
            if ($command eq "create"){
                my $task = $body->{task};
                if ($task){
                    my $is_created = $kernel->call("harvester","create_task",$task);
                    if ($is_created){
                        $server_response->{msg} = "success";
                    }
                }
            }
            elsif ($command eq "start"){
                my $task = $body->{task};
                if ($task){
                    my $uuid = $task->{uuid};
                    #Fetch from memory now...
                    my $is_started = $kernel->call("harvester","start_task", $uuid);
                    if ($is_started){
                        $server_response->{msg} = "success";
                    }
                }
            }
            elsif ($command eq "stop"){
                my $task = $body->{task};
                if ($task){
                    if ($task->{uuid}){
                        my $is_stopped = $kernel->call("harvester","stop_task",$task->{uuid});
                        if ($is_stopped){
                            $server_response->{msg} = "success";
                        }
                    }
                }
            }
            elsif ($command eq "delete"){
                my $task = $body->{task};
                if ($task){
                    if ($task->{uuid}){
                        my $is_deleted = $kernel->call("harvester","delete_task",$task->{uuid});
                        if ($is_deleted){
                            $server_response->{msg} = "success";
                        }
                    }
                }
            }
            elsif ($command eq "list"){
                my $tasks = $kernel->call("harvester","list_tasks");
                if ($tasks){
                    $server_response->{msg} = "success";
                    $server_response->{data} = $tasks;
                }
            }
        }
    };
    if ($@){
        #NOTE: An error most likely means that something other than a valid JSON string was received
        $logger->error($@);
    }

    if ($server_response){
        eval {
            my $client = $heap->{client}->{$wheel_id};
            my $json_message = to_json($server_response, { pretty => 1 });
            if ($json_message){
                $logger->debug("Server output: $json_message");
                $client->put($json_message);
            }
        };
        if ($@){
            #NOTE: An error means our response couldn't be serialised as JSON
            $logger->error($@);
        }
    }
}

1;
