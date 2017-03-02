package Koha::OAI::Harvester::Client;

# Copyright 2017 Prosentient Systems
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
use URI;
use IO::Socket::UNIX;
use IO::Select;
use JSON;

sub new {
    my ($class, $args) = @_;
    $args = {} unless defined $args;
    return bless ($args, $class);
}

sub connect {
    my ($self) =  @_;
    my $socket_uri = $self->{socket_uri};
    if ($socket_uri){
        my $uri = URI->new($socket_uri);
        if ($uri && $uri->scheme eq 'unix'){
            my $socket_path = $uri->path;
            my $socket = IO::Socket::UNIX->new(
                Type => IO::Socket::UNIX::SOCK_STREAM(),
                Peer => $socket_path,
            );
            if ($socket){
                my $select = new IO::Select();
                $select->add($socket);

                $self->{_select} = $select;
                $self->{_socket} = $socket;
                my $message = $self->_read();
                if ($message){
                    if ($message eq 'HELLO'){
                        $self->{_connected} = 1;
                        return 1;
                    }
                }
            }
            else {
                warn "Failed to create socket."
            }
        }
    }
    return 0;
}

sub create {
    my ($self,$task) = @_;
    my $message = {
        command => "create",
        body => {
            task => $task,
        }
    };
    my ($status) = $self->_exchange($message);
    return $status;
}

sub start {
    my ($self,$uuid) = @_;
    my $message = {
        command => "start",
        body => {
            task => {
                uuid => $uuid,
            },
        }
    };
    my ($status) = $self->_exchange($message);
    return $status;
}

sub stop {
    my ($self,$uuid) = @_;
    my $message = {
        command => "stop",
        body => {
            task => {
                uuid => $uuid,
            },
        }
    };
    my ($status) = $self->_exchange($message);
    return $status;
}

sub delete {
    my ($self,$uuid) = @_;
    my $message = {
        command => "delete",
        body => {
            task => {
                uuid => $uuid,
            },
        }
    };
    my ($status) = $self->_exchange($message);
    return $status;
}

sub list {
    my ($self) = @_;
    my $message = {
        command => "list",
    };
    my ($status,$tasks) = $self->_exchange($message);
    return $tasks;
}

sub _exchange {
    my ($self,$message) = @_;
    my $status = 0;
    my $data;
    if ($message){
        my $output = to_json($message);
        if ($output){
            $self->_write($output);
            my $json_response = $self->_read();
            if ($json_response){
                my $response = from_json($json_response);
                $data = $response->{data} if $response->{data};
                $status = 1 if $response->{msg} && $response->{msg} eq "success";
            }
        }
    }
    return ($status,$data);
}

sub _write {
    my ($self, $output) = @_;
    if ($output){
        if (my $select = $self->{_select}){
            if (my @filehandles = $select->can_write(5)){
                foreach my $filehandle (@filehandles){
                    #Localize output record separator as null
                    local $\ = "\x00";
                    print $filehandle $output;
                }
            }
        }
    }
}

sub _read {
    my ($self) = @_;
    if (my $select = $self->{_select}){
        if (my @filehandles = $select->can_read(5)){
            foreach my $filehandle (@filehandles){
                #Localize input record separator as null
                local $/ = "\x00";
                my $message = <$filehandle>;
                chomp($message) if $message;
                return $message;
            }
        }
    }
}

1;