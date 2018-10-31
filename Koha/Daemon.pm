package Koha::Daemon;

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
use POSIX; #For daemonizing
use Fcntl qw(:flock); #For pidfile

=head1 NAME

Koha::Daemon

=head1 SYNOPSIS

  use Koha::Daemon;
  my $daemon = Koha::Daemon->new({
    pidfile => "/path/to/file.pid",
    logfile => "/path/to/file.log",
    daemonize => 1,
  });
  $daemon->run();

=head1 METHODS

=head2 new

Create object

=head2 run

Run the daemon.

This method calls all the internal methods which
are do everything necessary to run the daemon.

=head1 INTERNAL METHODS

=head2 daemonize

Internal function for setting object up as a proper daemon
(e.g. forking, setting permissions, changing directories,
 closing file handles, etc.)

=head2 get_pidfile

Internal function to get a filehandle for the pidfile

=head2 lock_pidfile

Internal function to lock the pidfile, so that only one daemon
can run against this pidfile

=head2 log_to_file

Internal function to log to a file

=head2 make_pidfilehandle

Internal function to make a filehandle for pidfile

=head2 write_pidfile

Internal function to write pid to pidfile

=cut

sub new {
    my ($class, $args) = @_;
    $args = {} unless defined $args;
    return bless ($args, $class);
}

#######################################################################
#NOTE: On Debian, you can use the daemon binary to make a process into a daemon,
# but the following can be used if you don't want to use that program.

sub daemonize {
    my ($self) = @_;

    my $pid = fork;

    die "Couldn't fork: $!" unless defined($pid);
    if ($pid){
        exit; #Parent exit
    }

    #Become a session leader (ie detach program from controlling terminal)
    POSIX::setsid() or die "Can't start a new session: $!";

    #Change to known system directory
    chdir('/');

    #Reset the file creation mask so only the daemon owner can read/write files it creates
    umask(066);

    #Close inherited file handles, so that you can truly run in the background.
    open STDIN,  '<', '/dev/null';
    open STDOUT, '>', '/dev/null';
    open STDERR, '>&STDOUT';
}

sub log_to_file {
    my ($self,$logfile) = @_;

    #Open a filehandle to append to a log file
    my $opened = open(my $fh, '>>', $logfile);
    if ($opened){
        $fh->autoflush(1); #Make filehandle hot (ie don't buffer)
        *STDOUT = *$fh; #Re-assign STDOUT to LOG | --stdout
        *STDERR = *STDOUT; #Re-assign STDERR to STDOUT | --stderr
    }
    else {
        die "Unable to open a filehandle for $logfile: $!\n"; # --output
    }
}

sub make_pidfilehandle {
    my ($self,$pidfile) = @_;
    if ( ! -f $pidfile ){
        open(my $fh, '>', $pidfile) or die "Unable to write to $pidfile: $!\n";
        close($fh);
    }
    open(my $pidfilehandle, '+<', $pidfile) or die "Unable to open a filehandle for $pidfile: $!\n";
    return $pidfilehandle;
}

sub get_pidfile {
    my ($self,$pidfile) = @_;
    #NOTE: We need to save the filehandle in the object, so any locks persist for the life of the object
    my $pidfilehandle = $self->{pidfilehandle} ||= $self->make_pidfilehandle($pidfile);
    return $pidfilehandle;
}

sub lock_pidfile {
    my ($self,$pidfilehandle) = @_;
    my $locked;
    if (flock($pidfilehandle, LOCK_EX|LOCK_NB)){
        $locked = 1;

    }
    return $locked;
}

sub write_pidfile {
    my ($self,$pidfilehandle) = @_;
    if ($pidfilehandle){
        truncate($pidfilehandle, 0);
        print $pidfilehandle $$."\n" or die $!;
        #Flush the filehandle so you're not suffering from buffering
        $pidfilehandle->flush();
        return 1;
    }
}

sub run {
    my ($self) = @_;
    my $pidfile = $self->{pidfile};
    my $logfile = $self->{logfile};

    if ($pidfile){
        my $pidfilehandle = $self->get_pidfile($pidfile);
        if ($pidfilehandle){
            my $locked = $self->lock_pidfile($pidfilehandle);
            if ( ! $locked ) {
                die "$0 is unable to lock pidfile...\n";
            }
        }
    }

    if (my $configure = $self->{configure}){
        $configure->($self);
    }

    if ($self->{daemonize}){
        $self->daemonize();
    }

    if ($pidfile){
        my $pidfilehandle = $self->get_pidfile($pidfile);
        if ($pidfilehandle){
            $self->write_pidfile($pidfilehandle);
        }
    }

    if ($logfile){
        $self->log_to_file($logfile);
    }

    if (my $loop = $self->{loop}){
        $loop->($self);
    }
}

1;
