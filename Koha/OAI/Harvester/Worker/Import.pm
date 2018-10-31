package Koha::OAI::Harvester::Worker::Import;

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
use POE qw(Wheel::Run);
use JSON;
use XML::LibXML;

use C4::Context;
use C4::Matcher;
use Koha::OAI::Harvester::Import::Record;

use parent 'Koha::OAI::Harvester::Worker';

=head1 NAME

Koha::OAI::Harvester::Worker::Import

=head1 SYNOPSIS

    This is a module used by the OAI-PMH harvester internally.

    As a bare minimum, it must define an "on_start" method.

=head1 METHODS

=head2 new

     Create object

=cut

sub new {
    my ($class, $args) = @_;
    $args = {} unless defined $args;
    #NOTE: This type is used for logging and more importantly for registering with the harvester
    $args->{type} = "import" unless $args->{type};
    return bless ($args, $class);
}

=head2 on_start

    Internal event handler for starting the processing of a task

=cut

sub on_start {
    my ($self, $kernel, $heap, $postback,$task) = @_[OBJECT, KERNEL, HEAP, ARG0,ARG1];

    $kernel->call("harvester","register",$self->{type},$task->{uuid});

    $kernel->sig(cancel => "stop_worker");

    my $child = POE::Wheel::Run->new(
        ProgramArgs => [ $task ],
        Program => sub {
            my ($task,$args) = @_;

            my $debug = $args->{debug} // 0;

            if ($task){
                my $json_result = $task->{result};
                my $id = $task->{id};
                my $task_uuid = $task->{uuid};
                eval {
                    my $result = from_json($json_result);
                    if ($result){
                        my $repository = $result->{repository};
                        my $filenames = $result->{filenames};
                        my $filter = $result->{filter};
                        my $matcher_code = $result->{matcher_code};
                        my $frameworkcode = $result->{frameworkcode};
                        my $record_type = $result->{record_type};

                        my $matcher;
                        if ($matcher_code){
                            my $matcher_id = C4::Matcher::GetMatcherId($matcher_code);
                            $matcher = C4::Matcher->fetch($matcher_id);
                        }

                        foreach my $filename (@$filenames){
                            if ($filename){
                                if (-f $filename){
                                    my $dom = XML::LibXML->load_xml(location => $filename, { no_blanks => 1 });
                                    if ($dom){
                                        my $oai_record = Koha::OAI::Harvester::Import::Record->new({
                                            doc => $dom,
                                            repository => $repository,
                                        });
                                        if ($oai_record){
                                            my ($action,$linked_id) = $oai_record->import_record({
                                                filter => $filter,
                                                framework => $frameworkcode,
                                                record_type => $record_type,
                                                matcher => $matcher,
                                            });
                                            $debug && print STDOUT qq({ "import_result": { "task_uuid": "$task_uuid", "action": "$action", "filename": "$filename", "koha_id": "$linked_id" } }\n);
                                        }
                                    }
                                    my $unlinked = unlink $filename;
                                }
                            }
                        }
                    }
                };
                if ($@){
                    warn $@;
                }
                #NOTE: Even if the file doesn't exist, we still need to process the queue item.

                #NOTE: Don't do this via a postback in the parent process, as it's much faster to let the child process handle it.

                #NOTE: It's vital that files are unlinked before deleting from the database,
                #or you could get orphan files if the importer is interrupted.
                my $dbh = C4::Context->dbh;
                my $sql = "delete from oai_harvester_import_queue where id = ?";
                my $sth = $dbh->prepare($sql);
                $sth->execute($id);
            }
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

1;
