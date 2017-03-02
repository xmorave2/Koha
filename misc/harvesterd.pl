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
use Getopt::Long;
use Pod::Usage;
use Module::Load;
use Log::Log4perl qw(:easy);
use POE;
use YAML;

use C4::Context;
use Koha::Daemon;
use Koha::OAI::Harvester;
use Koha::OAI::Harvester::Listener;

binmode(STDOUT,':encoding(UTF-8)');
$|++;

my $help = 0;
my $daemonize = 0;

my ($socket_addr,$pidfile,$statefile,$spooldir);
my ($download_module,$import_module);
my ($batch,$download_workers,$import_workers,$import_poll);
my ($logfile,$log_level);
my $log_levels = {
    FATAL => $FATAL,
    ERROR => $ERROR,
    WARN => $WARN,
    INFO => $INFO,
    DEBUG => $DEBUG,
    TRACE => $TRACE,
};

my $context = C4::Context->new();
my $config_filename = $context->{config}->{oai_pmh_harvester_config};
if ($config_filename){
    my $config = YAML::LoadFile($config_filename);
    if ($config){
        $socket_addr = $config->{socket};
        $pidfile = $config->{pidfile};
        $statefile = $config->{statefile};
        $spooldir = $config->{spooldir};
        $logfile = $config->{logfile};
        $log_level = $config->{loglevel};
        $download_module = $config->{download_module};
        $import_module = $config->{import_module};
        $batch = $config->{download_batch};
        $download_workers = $config->{download_workers};
        $import_workers = $config->{import_workers};
        $import_poll = $config->{import_poll};
    }
}

GetOptions(
    "help|?"            => \$help,
    "daemon"            => \$daemonize,
    "socket-uri=s"          => \$socket_addr,
    "pid-file=s"             => \$pidfile,
    "state-file=s"      => \$statefile,
    "spool-dir=s"       => \$spooldir,
    "log-file=s"             => \$logfile,
    "log-level=s"       => \$log_level,
    "download-module=s" => \$download_module,
    "import-module=s"   => \$import_module,
) or pod2usage(2);
pod2usage(1) if $help;

my $level = ( $log_level && $log_levels->{$log_level} ) ? $log_levels->{$log_level} : $log_levels->{WARN};
Log::Log4perl->easy_init(
    {
        level => $level,
        file => "STDOUT",
        layout   => '[%d{yyyy-MM-dd HH:mm:ss}][%p] %m%n',
    }
);
my $logger = Log::Log4perl->get_logger();

unless($download_module){
    $download_module = "Koha::OAI::Harvester::Worker::Download::Stream";
}
unless($import_module){
    $import_module = "Koha::OAI::Harvester::Worker::Import";
}

foreach my $module ( $download_module, $import_module ){
    load $module;
}
my $downloader = $download_module->new({
    logger => $logger,
    batch => $batch,
});
my $importer = $import_module->new({
    logger => $logger,
});

my $daemon = Koha::Daemon->new({
    pidfile => $pidfile,
    logfile => $logfile,
    daemonize => $daemonize,
});
$daemon->run();

my $harvester = Koha::OAI::Harvester->spawn({
    Downloader => $downloader,
    DownloaderWorkers => $download_workers,
    Importer => $importer,
    ImporterWorkers => $import_workers,
    ImportQueuePoll => $import_poll,
    logger => $logger,
    state_file => $statefile,
    spooldir => $spooldir,
});

my $listener = Koha::OAI::Harvester::Listener->spawn({
    logger => $logger,
    socket => $socket_addr,
});

$logger->info("OAI-PMH harvester started.");

POE::Kernel->run();

exit;

=head1 NAME

harvesterd.pl - a daemon that asynchronously sends OAI-PMH requests and imports OAI-PMH records

=head1 SYNOPSIS

KOHA_CONF=/path/to/koha-conf.xml ./harvesterd.pl

=head1 OPTIONS

=over 8

=item B<--help>

Print a brief help message and exits.

=item B<--daemon>

Run program as a daemon (ie fork process, setsid, chdir to root, reset umask,
and close STDIN, STDOUT, and STDERR).

=item B<--log-file>

Specify a file to which to log STDOUT and STDERR.

=item B<--pid-file>

Specify a file to store the process id (this prevents multiple copies of the program
from running at the same time).

=item B<--socket-uri>

Specify a URI to use for the UNIX socket used to communicate with the daemon.
(e.g. unix:/path/to/socket.sock)

=item B<--state-file>

Specify a filename to use for storing the harvester's in-memory state.

In the event that the harvester crashes, it can resume from where it stopped.

=item B<--spool-dir>

Specify a directory to store downloaded OAI-PMH records prior to import.

=item B<--log-level>

Specify a log level for logging. The logger uses Log4Perl, which provides
FATAL, ERROR, WARN, INFO, DEBUG, and TRACE in order of descending priority.

Defaults to WARN level.

=item B<--download-module>

Specify a Perl module to use for downloading records. This is a specialty module,
which has particular requirements, so only advanced users should use this option.

=item B<--import-module>

Specify a Perl module to use for importing records. This is a specialty module,
which has particular requirements, so only advanced users should use this option.

=back

=cut
