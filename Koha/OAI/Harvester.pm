package Koha::OAI::Harvester;

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
use POE qw(Component::JobQueue);
use JSON;
use Sereal::Encoder;
use Sereal::Decoder;
use IO::Handle;
use File::Copy;
use File::Path qw(make_path remove_tree);
use DateTime;
use DateTime::Format::Strptime;

use C4::Context;
use Koha::Database;

=head1 API

=head2 Class Methods

=cut

my $day_granularity = DateTime::Format::Strptime->new(
    pattern   => '%F',
);
my $seconds_granularity = DateTime::Format::Strptime->new(
    pattern   => '%FT%TZ',
);

sub new {
    my ($class, $args) = @_;
    $args = {} unless defined $args;
    return bless ($args, $class);
}

sub spawn {
    my ($class, $args) = @_;
    my $self = $class->new($args);
    my $downloader = $self->{Downloader};
    my $importer = $self->{Importer};
    my $download_worker_limit = ( $self->{DownloaderWorkers} && int($self->{DownloaderWorkers}) ) ? $self->{DownloaderWorkers} : 1;
    my $import_worker_limit = ( $self->{ImporterWorkers} && int($self->{ImporterWorkers}) ) ? $self->{ImporterWorkers} : 1;
    my $import_queue_poll = ( $self->{ImportQueuePoll} && int($self->{ImportQueuePoll}) ) ? $self->{ImportQueuePoll} : 5;

    #NOTE: This job queue should always be created before the
    #harvester so that you can start download jobs immediately
    #upon spawning the harvester.
    POE::Component::JobQueue->spawn(
        Alias         => 'oai-downloader',
        WorkerLimit   => $download_worker_limit,
        Worker        => sub {
            my ($postback, $task) = @_;
            if ($downloader){
                if ($task->{status} eq "active"){
                    $downloader->run({
                        postback => $postback,
                        task => $task,
                   });
                }
            }
        },
        Passive => {},
    );

    POE::Session->create(
        object_states => [
            $self => {
                _start => "on_start",
                get_task => "get_task",
                list_tasks => "list_tasks",
                create_task => "create_task",
                start_task => "start_task",
                stop_task => "stop_task",
                delete_task => "delete_task",
                repeat_task => "repeat_task",
                register => "register",
                deregister => "deregister",
                restore_state => "restore_state",
                save_state => "save_state",
                is_task_finished => "is_task_finished",
                does_task_repeat => "does_task_repeat",
                download_postback => "download_postback",
                reset_imports_status => "reset_imports_status",
            },
        ],
    );

    POE::Component::JobQueue->spawn(
        Alias         => 'oai-importer',
        WorkerLimit   => $import_worker_limit,
        Worker        => sub {
            my $meta_postback = shift;

            #NOTE: We need to only retrieve queue items for active tasks. Otherwise,
            #the importer will just spin its wheels on inactive tasks and do nothing.
            my $active_tasks = $poe_kernel->call("harvester","list_tasks","active");
            my @active_uuids = map { $_->{uuid} } @$active_tasks;

            my $schema = Koha::Database->new()->schema();
            my $rs = $schema->resultset('OaiHarvesterImportQueue')->search({
                uuid => \@active_uuids,
                status => "new"
            },{
                order_by => { -asc => 'id' },
                rows => 1,
            });
            my $result = $rs->first;
            if ($result){
                $result->status("wip");
                $result->update;
                my $task = {
                    id => $result->id,
                    uuid => $result->uuid,
                    result => $result->result,
                };

                my $postback = $meta_postback->($task);
                $importer->run({
                    postback => $postback,
                    task => $task,
                });
            }
        },
        Active => {
            PollInterval => $import_queue_poll,
            AckAlias => undef,
            AckState => undef,
        },
    );

    return;
}

sub on_start {
    my ($self, $kernel, $heap) = @_[OBJECT, KERNEL,HEAP];
    $kernel->alias_set('harvester');
    $heap->{scoreboard} = {};

    #Reset any 'wip' imports to 'new' so they can be re-tried.
    $kernel->call("harvester","reset_imports_status");

    #Restore state from state file
    $kernel->call("harvester","restore_state");
}

#NOTE: This isn't really implemented at the moment, as it's not really necessary.
sub download_postback {
    my ($kernel, $request_packet, $response_packet) = @_[KERNEL, ARG0, ARG1];
    my $message = $response_packet->[0];
}

=head3 deregister

    Remove the worker session from the harvester's in-memory scoreboard,
    unset the downloading flag if downloading is completed.

=cut

sub deregister {
    my ($self, $kernel, $heap, $session, $sender, $type) = @_[OBJECT, KERNEL,HEAP,SESSION,SENDER,ARG0];

    my $scoreboard = $heap->{scoreboard};

    my $logger = $self->{logger};
    $logger->debug("Start deregistering $sender as $type task");

    my $task_uuid = delete $scoreboard->{session}->{$sender};
    #NOTE: If you don't check each step of the hashref, autovivication can lead to surprises.
    if ($task_uuid){
        if ($scoreboard->{task}->{$task_uuid}){
            if ($scoreboard->{task}->{$task_uuid}->{$type}){
                delete $scoreboard->{task}->{$task_uuid}->{$type}->{$sender};
            }
        }
    }

    my $task = $heap->{tasks}->{$task_uuid};
    if ($task && $task->{status} && ($task->{status} eq "active") ){
        #NOTE: Each task only has 1 download session, so we can now set/unset flags for the task.
        #NOTE: We should unset the downloading flag, if we're not going to repeat the task.
        if ($type eq "download"){
            my $task_repeats = $kernel->call("harvester","does_task_repeat",$task_uuid);
            if ($task_repeats){
                my $interval = $task->{interval};

                $task->{effective_from} = delete $task->{effective_until};
                $task->{download_timer} = $kernel->delay_set("repeat_task", $interval, $task_uuid);
            }
            else {
                $task->{downloading} = 0;
                $kernel->call("harvester","save_state");
                $kernel->call("harvester","is_task_finished",$task_uuid);
            }
        }
        elsif ($type eq 'import'){
            $kernel->call("harvester","is_task_finished",$task_uuid);
        }
    }
    $logger->debug("End deregistering $sender as $type task");
}


=head3 is_task_finished

    This event handler checks if the task has finished downloading and importing record.
    If it is finished downloading and importing, the task is deleted from the harvester.

    This only applies to non-repeating tasks.

=cut

sub is_task_finished {
    my ($self, $kernel, $heap, $session, $uuid) = @_[OBJECT, KERNEL,HEAP,SESSION,ARG0];
    my $task = $kernel->call("harvester","get_task",$uuid);
    if ($task && (! $task->{downloading}) ){
        my $count = $self->get_import_count_for_task($uuid);
        if ( ! $count ) {
            #Clear this task out of the harvester as it's finished.
            $kernel->call("harvester","delete_task",$uuid);
            return 1;
        }
    }
    return 0;
}

sub register {
    my ($self, $kernel, $heap, $session, $sender, $type, $task_uuid) = @_[OBJECT, KERNEL,HEAP,SESSION,SENDER,ARG0,ARG1];
    my $logger = $self->{logger};

    my $scoreboard = $heap->{scoreboard};


    if ($type && $task_uuid){
        $logger->debug("Registering $sender as $type for $task_uuid");

        my $task = $heap->{tasks}->{$task_uuid};
        if ($task){

            if ($type){
                #Register the task uuid with the session id as a key for later recall
                $scoreboard->{session}->{$sender} = $task_uuid;

                #Register the session id as a certain type of session for a task
                $scoreboard->{task}->{$task_uuid}->{$type}->{$sender} = 1;

                if ($type eq "download"){
                    $task->{downloading} = 1;

                    my $task_repeats = $kernel->call("harvester","does_task_repeat",$task_uuid);
                    if ($task_repeats){

                        #NOTE: Set an effective until, so we know we're not getting records any newer than
                        #this moment.
                        my $dt = DateTime->now();
                        if ($dt){
                            #NOTE: Ideally, I'd like to make sure that we can use 'seconds' granularity, but
                            #it's valid for 'from' to be null, so it's impossible to know from the data whether
                            #or not the repository will support the seconds granularity.
                            #NOTE: Ideally, it would be good to use either 'day' granularity or 'seconds' granularity,
                            #but at the moment the interval is expressed as seconds only.
                            $dt->set_formatter($seconds_granularity);
                            $task->{effective_until} = "$dt";
                        }
                    }

                    $kernel->call("harvester","save_state");
                }
            }
        }
    }
}

sub does_task_repeat {
    my ($self, $kernel, $heap, $session, $uuid) = @_[OBJECT, KERNEL,HEAP,SESSION,ARG0];
    my $task = $kernel->call("harvester","get_task",$uuid);
    if ($task){
        my $interval = $task->{interval};
        my $parameters = $task->{parameters};
        if ($parameters){
            my $oai_pmh = $parameters->{oai_pmh};
            if ($oai_pmh){
                if ( $interval && ($oai_pmh->{verb} eq "ListRecords") && (! $oai_pmh->{until}) ){
                    return 1;
                }
            }
        }
    }
    return 0;
}



sub reset_imports_status {
    my ($self, $kernel, $heap, $session) = @_[OBJECT, KERNEL,HEAP,SESSION];

    my $schema = Koha::Database->new()->schema();
    my $rs = $schema->resultset('OaiHarvesterImportQueue')->search({
                status => "wip",
    });
    $rs->update({
        status => "new",
    });
}

sub restore_state {
    my ($self, $kernel, $heap, $session) = @_[OBJECT, KERNEL,HEAP,SESSION];

    my $state_file = $self->{state_file};
    if ($state_file){
        my $state_backup = "$state_file~";

        #NOTE: If there is a state backup, it means we crashed while saving the state. Otherwise,
        #let's try the regular state file if it exists.
        my $file_to_restore = ( -f $state_backup ) ? $state_backup : ( ( -f $state_file ) ? $state_file : undef );
        if ( $file_to_restore ){
            my $opened = open( my $fh, '<', $file_to_restore ) or die "Couldn't open state: $!";
            if ($opened){
                local $/;
                my $in = <$fh>;
                my $decoder = Sereal::Decoder->new;
                my $state = $decoder->decode($in);
                if ($state){
                    if ($state->{tasks}){
                        #Restore tasks from our saved state
                        $heap->{tasks} = $state->{tasks};
                        foreach my $uuid ( keys %{$heap->{tasks}} ){
                            my $task = $heap->{tasks}->{$uuid};

                            #If tasks were still downloading, restart the task
                            if ( ($task->{status} && $task->{status} eq "active") && $task->{downloading} ){
                                $task->{status} = "new";
                                $kernel->call("harvester","start_task",$task->{uuid});
                            }
                        }
                    }
                }
            }
        }
    }
}

sub save_state {
    my ($self, $kernel, $heap, $session) = @_[OBJECT, KERNEL,HEAP,SESSION];
    my $state_file = $self->{state_file};
    my $state_backup = "$state_file~";

    #Make a backup of existing state record
    my $moved = move($state_file,$state_backup);

    my $opened = open(my $fh, ">", $state_file) or die "Couldn't save state: $!";
    if ($opened){
        $fh->autoflush(1);
        my $tasks = $heap->{tasks};
        my $harvester_state = {
            tasks => $tasks,
        };
        my $encoder = Sereal::Encoder->new;
        my $out = $encoder->encode($harvester_state);
        local $\;
        my $printed = print $fh $out;
        if ($printed){
            close $fh;
            unlink($state_backup);
            return 1;
        }
    }
    return 0;
}

=head3 get_task

    This event handler returns a task from a harvester using the task's
    uuid as an argument.

=cut

sub get_task {
    my ($self, $kernel, $heap, $session, $uuid, $sender) = @_[OBJECT, KERNEL,HEAP,SESSION,ARG0, SENDER];

    if ( ! $uuid && $sender ){
        my $scoreboard = $heap->{scoreboard};
        my $uuid_by_session = $scoreboard->{session}->{$sender};
        if ($uuid_by_session){
            $uuid = $uuid_by_session;
        }
    }

    my $tasks = $heap->{tasks};
    if ($tasks && $uuid){
        my $task = $tasks->{$uuid};
        if ($task){
            return $task;
        }
    }
    return 0;
}

=head3 get_import_count_for_task

=cut

sub get_import_count_for_task {
    my ($self,$uuid) = @_;
    my $count = undef;
    if ($uuid){
        my $schema = Koha::Database->new()->schema();
        my $items = $schema->resultset('OaiHarvesterImportQueue')->search({
            uuid => $uuid,
        });
        $count = $items->count;
    }
    return $count;
}

=head3 list_tasks

    This event handler returns a list of tasks that have been submitted
    to the harvester. It returns data like uuid, status, parameters,
    number of pending imports, etc.

=cut

sub list_tasks {
    my ($self, $kernel, $heap, $session, $status) = @_[OBJECT, KERNEL,HEAP,SESSION, ARG0];
    my $schema = Koha::Database->new()->schema();
    my @tasks = ();
    foreach my $uuid (sort keys %{$heap->{tasks}}){
        my $task = $heap->{tasks}->{$uuid};
        my $items = $schema->resultset('OaiHarvesterImportQueue')->search({
            uuid => $uuid,
        });
        my $count = $items->count // 0;
        $task->{pending_imports} = $count;
        if ( ( ! $status ) || ( $status && $status eq $task->{status} ) ){
            push(@tasks, $task);
        }

    }
    return \@tasks;
}

=head3 create_task

    This event handler creates a spool directory for the task's imports.
    It also adds it to the harvester's memory and then saves memory to
    a persistent datastore.

    Newly created tasks have a status of "new".

=cut

sub create_task {
    my ($self, $kernel, $heap, $session, $incoming_task) = @_[OBJECT, KERNEL,HEAP,SESSION,ARG0];
    my $logger = $self->{logger};
    if ($incoming_task){
        my $uuid = $incoming_task->{uuid};
        if ( ! $heap->{tasks}->{$uuid} ){

            #Step One: assign a spool directory to this task
            my $spooldir = $self->{spooldir} // "/tmp";
            my $task_spooldir = "$spooldir/$uuid";
            if ( ! -d $task_spooldir ){
                my $made_spool_directory = make_path($task_spooldir);
                if ( ! $made_spool_directory ){
                    if ($logger){
                        $logger->warn("Unable to make task-specific spool directory at '$task_spooldir'");
                    }
                    return 0;
                }
            }
            $incoming_task->{spooldir} = $task_spooldir;

            #Step Two: assign new status
            $incoming_task->{status} = "new";

            #Step Three: add task to harvester's memory
            $heap->{tasks}->{ $uuid } = $incoming_task;

            #Step Four: save state
            $kernel->call($session,"save_state");
            return 1;
        }
    }
    return 0;
}

=head3 start_task

    This event handler marks a task as active in the harvester's memory,
    save the memory to a persistent datastore, then enqueues the task,
    so that it can be directed to the next available download worker.

    Newly started tasks have a status of "active".

=cut

sub start_task {
    my ($self, $session,$kernel,$heap,$uuid) = @_[OBJECT, SESSION,KERNEL,HEAP,ARG0];
    my $task = $heap->{tasks}->{$uuid};
    if ($task){
        if ( $task->{status} ne "active" ){

            #Clear any pre-existing error states
            delete $task->{error} if $task->{error};

            #Step One: mark task as active
            $task->{status} = "active";

            #Step Two: save state
            $kernel->call("harvester","save_state");

            #Step Three: enqueue task
            $kernel->post("oai-downloader",'enqueue','download_postback', $task);

            return 1;
        }
    }
    return 0;
}

=head3 repeat_task



=cut

sub repeat_task {
    my ($self, $session,$kernel,$heap,$uuid) = @_[OBJECT, SESSION,KERNEL,HEAP,ARG0];
    my $task = $heap->{tasks}->{$uuid};
    if ($task){
        my $interval = $task->{interval};
        if ($task->{downloading} && $interval){
            $kernel->post("oai-downloader",'enqueue','download_postback', $task);
        }
    }
}

=head3 stop_task

    This event handler prevents new workers from spawning, kills
    existing workers, and stops pending imports from being imported.

    Newly stopped tasks have a status of "stopped".

=cut

sub stop_task {
    my ($self, $kernel, $heap, $session, $sender, $task_uuid) = @_[OBJECT, KERNEL,HEAP,SESSION,SENDER,ARG0];

    my $task = $heap->{tasks}->{$task_uuid};

    if ($task && $task->{status} && $task->{status} ne "stopped" ){

        #Step One: deactivate task, so no new workers can be started
        $task->{status} = "stopped";
        #NOTE: You could also clear timers for new downloads, but that's probably unnecessary because of this step.

        #Step Two: kill workers
        my $scoreboard = $heap->{scoreboard};
        my $session_types = $scoreboard->{task}->{$task_uuid};
        if ($session_types){
            foreach my $type ( keys %$session_types ){
                my $sessions = $session_types->{$type};
                if ($sessions){
                    foreach my $session (keys %$sessions){
                        if ($session){
                            $kernel->signal($session, "cancel");
                        }
                    }
                }
            }
            #Remove the task uuid from the task key of the scoreboard
            delete $scoreboard->{task}->{$task_uuid};
            #NOTE: The task uuid will still exist under the session key,
            #but the sessions will deregister themselves and clean that up for you.
        }

        #Step Three: stop pending imports for this task
        my $schema = Koha::Database->new()->schema();
        my $items = $schema->resultset('OaiHarvesterImportQueue')->search({
            uuid => $task_uuid,
        });
        my $rows_updated = $items->update({
            status => "stopped",
        });

        #Step Four: save state
        $kernel->call("harvester","save_state");
        return 1;
    }
    return 0;
}

=head3 delete_task

    Deleted tasks are stopped, pending imports are deleted from the
    database and file system, and then the task is removed from the harvester.

=cut

sub delete_task {
    my ($self, $kernel, $heap, $session, $task_uuid) = @_[OBJECT, KERNEL,HEAP,SESSION,ARG0];

    my $task = $heap->{tasks}->{$task_uuid};
    if ($task){
        #Step One: stop task
        $kernel->call($session,"stop_task",$task_uuid);

        #Step Two: delete pending imports in database
        my $schema = Koha::Database->new()->schema();
        my $items = $schema->resultset('OaiHarvesterImportQueue')->search({
            uuid => $task_uuid,
        });
        if ($items){
            my $rows_deleted = $items->delete;
            #NOTE: shows 0E0 instead of 0
        }

        #Step Three: remove task specific spool directory and files within it
        my $spooldir = $task->{spooldir};
        if ($spooldir){
            my $files_deleted = remove_tree($spooldir, { safe => 1 });
        }

        delete $heap->{tasks}->{$task_uuid};

        #Step Four: save state
        $kernel->call("harvester","save_state");
        return 1;
    }
    return 0;
}

1;
