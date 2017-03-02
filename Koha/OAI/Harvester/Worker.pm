package Koha::OAI::Harvester::Worker;

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
use POE;
use DateTime;
use JSON;

sub new {
    my ($class, $args) = @_;
    $args = {} unless defined $args;
    $args->{type} = "worker" unless $args->{type};
    return bless ($args, $class);
}

sub run {
    my ($self,$args) = @_;
    my $postback = $args->{postback};
    my $task = $args->{task};

    POE::Session->create(
        object_states => [
            $self => {
                _start           => "on_start",
                got_child_stderr => "on_child_stderr",
                got_child_close  => "on_child_close",
                got_child_signal => "on_child_signal",
                got_child_stdout => "on_child_stdout",
                stop_worker      => "stop_worker",
                _stop            => "on_stop",
            },
        ],
        args => [
            $postback,
            $task,
        ],
    );
}

sub stop_worker {
    my ($self,$heap) = @_[OBJECT,HEAP];
    if (my $child_processes = $heap->{children_by_pid}){
        foreach my $child_pid (keys %$child_processes){
            my $child = $child_processes->{$child_pid};
            $child->kill();
        }
    }
}


sub on_stop {
    my ($self,$kernel) = @_[OBJECT,KERNEL];

    #Deregister the worker session from the harvester's roster of workers
    $kernel->call("harvester","deregister",$self->{type});
}

# Wheel event, including the wheel's ID.
sub on_child_stdout {
    my ($self, $stdout_line, $wheel_id) = @_[OBJECT, ARG0, ARG1];
    my $type = $self->{type};
    my $child = $_[HEAP]{children_by_wid}{$wheel_id};
    my $logger = $self->{logger};
    if ($logger){
        $logger->debug("[$type][pid ".$child->PID."][STDOUT] $stdout_line");
    }

    my $postback = $_[HEAP]{postback};
    if ($postback){
        eval {
            my $message = from_json($stdout_line);
            if ($message){
                $postback->($message);
            }
        };
    }
}

# Wheel event, including the wheel's ID.
sub on_child_stderr {
    my ($self,$stderr_line, $wheel_id) = @_[OBJECT, ARG0, ARG1];
    my $type = $self->{type};
    my $child = $_[HEAP]{children_by_wid}{$wheel_id};
    my $logger = $self->{logger};
    if ($logger){
        $logger->debug("[$type][pid ".$child->PID."][STDERR] $stderr_line");
    }
}

# Wheel event, including the wheel's ID.
sub on_child_close {
    my ($self,$heap,$wheel_id) = @_[OBJECT,HEAP,ARG0];
    my $type = $self->{type};
    my $logger = $self->{logger};

    my $child = delete $heap->{children_by_wid}->{$wheel_id};

    # May have been reaped by on_child_signal().
    unless (defined $child) {
        if ($logger){
            $logger->debug("[$type][wid $wheel_id] closed all pipes");
        }
        return;
    }
    if ($logger){
        $logger->debug("[$type][pid ".$child->PID."] closed all pipes");
    }
    delete $heap->{children_by_pid}->{$child->PID};
}

sub on_child_signal {
    my ($self,$kernel,$pid,$status) = @_[OBJECT,KERNEL,ARG1,ARG2];
    my $type = $self->{type};
    my $logger = $self->{logger};
    if ($logger){
        $logger->debug("[$type][pid $pid] exited with status $status");
    }

    my $child = delete $_[HEAP]{children_by_pid}{$_[ARG1]};

    # May have been reaped by on_child_close().
    return unless defined $child;

    delete $_[HEAP]{children_by_wid}{$child->ID};

    #If the child doesn't complete successfully, we lodge an error
    #and stop the task.
    if ($status != 0){
        my $task = $kernel->call("harvester","get_task");
        if ($task){
            $task->{error} = 1;
            my $uuid = $task->{uuid};
            if ($uuid){
                $kernel->call("harvester","stop_task",$uuid);
            }
        }
    }
}

1;
