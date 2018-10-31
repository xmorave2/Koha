package Koha::OAI::Harvester::Downloader;

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
use XML::LibXML::Reader;
use IO::Handle;
use JSON;

=head1 NAME

Koha::OAI::Harvester::Downloader

=head1 SYNOPSIS

    use Koha::OAI::Harvester::Downloader;
    my $oai_downloader = Koha::OAI::Harvester::Downloader->new();

    This class is used within a Koha::OAI::Harvester::Work::Download:: module.

=head1 METHODS

=head2 new

    Create object

=cut

sub new {
    my ($class, $args) = @_;
    $args = {} unless defined $args;
    return bless ($args, $class);
}

=head2 BuildURL

    Takes a baseURL and a mix of required and optional OAI-PMH arguments,
    and makes them into a suitable URL for an OAI-PMH request.

=cut

sub BuildURL {
    my ($self, $args) = @_;
    my $baseURL = $args->{baseURL};
    my $url = URI->new($baseURL);
    if ($url && $url->isa("URI")){
        my $verb = $args->{verb};
        if ($verb){
            my %parameters = (
                verb => $verb,
            );
            if ($verb eq "ListRecords"){
                my $resumptionToken = $args->{resumptionToken};
                my $metadataPrefix = $args->{metadataPrefix};
                if ($resumptionToken){
                    $parameters{resumptionToken} = $resumptionToken;
                }
                elsif ($metadataPrefix){
                    $parameters{metadataPrefix} = $metadataPrefix;
                    #Only add optional parameters if they're provided
                    foreach my $param ( qw( from until set ) ){
                        $parameters{$param} = $args->{$param} if $args->{$param};
                    }
                }
                else {
                    warn "BuildURL() requires an argument of either resumptionToken or metadataPrefix";
                    return;
                }
            }
            elsif ($verb eq "GetRecord"){
                my $metadataPrefix = $args->{metadataPrefix};
                my $identifier = $args->{identifier};
                if ($metadataPrefix && $identifier){
                    $parameters{metadataPrefix} = $metadataPrefix;
                    $parameters{identifier} = $identifier;
                }
                else {
                    warn "BuildURL() requires an argument of metadataPrefix and an argument of identifier";
                    return;
                }
            }
            $url->query_form(%parameters);
            return $url;
        }
        else {
            warn "BuildURL() requires a verb of GetRecord or ListRecords";
            return;
        }
    }
    else {
        warn "BuildURL() requires a base URL of type URI.";
        return;
    }
}

=head2 GetXMLStream

    Fork a child process to send the HTTP request, which sends chunks
    of XML via a pipe to the parent process.

    The parent process creates and returns a XML::LibXML::Reader object,
    which reads the XML stream coming through the pipe.

    Normally, using a DOM reader, you must wait to read the entire XML document
    into memory. However, using a stream reader, chunks are read into memory,
    processed, then discarded. It's faster and more efficient.

=cut

sub GetXMLStream {
    my ($self, $args) = @_;
    my $url = $args->{url};
    my $user_agent = $args->{user_agent};
    if ($url && $user_agent){
        pipe( CHILD, PARENT ) or die "Cannot created connected pipes: $!";
        CHILD->autoflush(1);
        PARENT->autoflush(1);
        if ( my $pid = fork ){
            #Parent process
            close PARENT;
            return \*CHILD;
        }
        else {
            #Child process
            close CHILD;
            my $response = $self->_request({
                url => $url,
                user_agent => $user_agent,
                file_handle => \*PARENT,
            });
            if ($response && $response->is_success){
                #HTTP request has successfully finished, so we close the file handle and exit the process
                close PARENT;
                CORE::exit(); #some modules like mod_perl redefine exit
            }
            else {
                warn "[child $$] OAI-PMH unsuccessful. Response status: ".$response->status_line."\n" if $response;
                CORE::exit();
            }
        }
    }
    else {
        warn "GetXMLStream() requires a 'url' argument and a 'user_agent' argument";
        return;
    }
}

sub _request {
    my ($self, $args) = @_;
    my $url = $args->{url};
    my $user_agent = $args->{user_agent};
    my $fh = $args->{file_handle};

    if ($url && $user_agent && $fh){
        my $request = HTTP::Request->new( GET => $url );
        my $response = $user_agent->request( $request, sub {
                my ($chunk_of_data, $ref_to_response, $ref_to_protocol) = @_;
                print $fh $chunk_of_data;
        });
        return $response;
    }
    else {
        warn "_request() requires a 'url' argument, 'user_agent' argument, and 'file_handle' argument.";
        return;
    }
}

=head2 ParseXMLStream

    Parse XML using XML::LibXML::Reader from a file handle (e.g. a stream)

=cut


sub ParseXMLStream {
    my ($self, $args) = @_;

    my $each_callback = $args->{each_callback};
    my $fh = $args->{file_handle};
    if ($fh){
        my $reader = XML::LibXML::Reader->new( FD => $fh, no_blanks => 1 );
        my $pattern = XML::LibXML::Pattern->new('oai:OAI-PMH|/oai:OAI-PMH/*', { 'oai' => "http://www.openarchives.org/OAI/2.0/" });

        my $repository;

        warn "Start parsing...";
        while (my $rv = $reader->nextPatternMatch($pattern)){
            #$rv == 1; successful
            #$rv == 0; end of document reached
            #$rv == -1; error
            if ($rv == -1){
                die "Parser error!";
            }
            #NOTE: We do this so we only get the opening tag of the element.
            next unless $reader->nodeType == XML_READER_TYPE_ELEMENT;

            my $localname = $reader->localName;
            if ( $localname eq "request" ){
                my $node = $reader->copyCurrentNode(1);
                $repository = $node->textContent;
            }
            elsif ( $localname eq "error" ){
                #See https://www.openarchives.org/OAI/openarchivesprotocol.html#ErrorConditions
                #We should probably die under all circumstances except "noRecordsMatch"
                my $node = $reader->copyCurrentNode(1);
                if ($node){
                    my $code = $node->getAttribute("code");
                    if ($code){
                        if ($code ne "noRecordsMatch"){
                            warn "Error code: $code";
                            die;
                        }
                    }
                }
            }
            elsif ( ($localname eq "ListRecords") || ($localname eq "GetRecord") ){
                my $each_pattern = XML::LibXML::Pattern->new('//oai:record|oai:resumptionToken', { 'oai' => "http://www.openarchives.org/OAI/2.0/" });
                while (my $each_rv =  $reader->nextPatternMatch($each_pattern)){
                    if ($rv == "-1"){
                        #NOTE: -1 denotes an error state
                        warn "Error getting pattern match";
                    }
                    next unless $reader->nodeType == XML_READER_TYPE_ELEMENT;
                    if ($reader->localName eq "record"){
                        my $node = $reader->copyCurrentNode(1);
                        #NOTE: Without the UTF-8 flag, UTF-8 data will be corrupted.
                        my $document = XML::LibXML::Document->new('1.0', 'UTF-8');
                        $document->setDocumentElement($node);

                       #Per record callback
                        if ($each_callback){
                            $each_callback->({
                                repository => $repository,
                                document => $document,
                            });
                        }
                    }
                    elsif ($reader->localName eq "resumptionToken"){
                        my $resumptionToken = $reader->readInnerXml;
                        return ($resumptionToken,$repository);

                    }
                }
            }
        } #/OAI-PMH document match
    }
    else {
        warn "ParseXMLStream() requires a 'file_handle' argument.";
    }
}

=head2 harvest

    Given a URL and a user-agent, start downloading OAI-PMH records from
    that URL.

=cut

sub harvest {
    my ($self,$args) = @_;
    my $url = $args->{url};
    my $ua = $args->{user_agent};
    my $callback = $args->{callback};
    my $complete_callback = $args->{complete_callback};

    if ($url && $ua){

        #NOTE: http://search.cpan.org/~shlomif/XML-LibXML-2.0128/lib/XML/LibXML/Parser.pod#ERROR_REPORTING
        while($url){
            warn "URL = $url";
            warn "Creating child process to download and feed parent process parser.";
            my $stream = $self->GetXMLStream({
                url => $url,
                user_agent => $ua,
            });

            warn "Creating parent process parser.";
            my ($resumptionToken) = $self->ParseXMLStream({
                file_handle => $stream,
                each_callback => $callback,
            });
            warn "Finished parsing current XML document.";

            if ($resumptionToken){
                #If there's a resumptionToken at the end of the stream,
                #we build a new URL and repeat this process again.
                $url->query_form({
                    verb => "ListRecords",
                    resumptionToken => $resumptionToken,
                });
            }
            else {
                warn "Finished harvest.";
                last;
            }

            warn "Reap child process downloader.";
            #Reap the dead child requester process before performing another request,
            #so we don't fill up the process table with zombie children.
            while ((my $child = waitpid(-1, 0)) > 0) {
                warn "Parent $$ reaped child process $child" . ($? ? " with exit code $?" : '') . ".\n";
            }
        }

        if ($complete_callback){
            warn "Run complete callback.";

            #Clear query string
            $url->query_form({});

            #Run complete callback using the actual URL from the request.
            $complete_callback->({
                repository => $url,
            });
        }
    }
}

1;
