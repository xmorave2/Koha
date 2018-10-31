package Koha::OAI::Harvester::Import::Record;

# Copyright 2016 Prosentient Systems
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
use XML::LibXML;
use XML::LibXSLT;
use URI;
use File::Basename;

use C4::Context;
use C4::Biblio;

use Koha::OAI::Harvester::Import::MARCXML;
use Koha::OAI::Harvester::Biblios;
use Koha::OAI::Harvester::History;

=head1 NAME

Koha::OAI::Harvester::Import::Record

=head1 SYNOPSIS

    use Koha::OAI::Harvester::Import::Record;
    my $oai_record = Koha::OAI::Harvester::Import::Record->new({
        doc => $dom,
        repository => $repository,
    });

=head1 METHODS

=head2 new

    Create object

=cut

sub new {
    my ($class, $args) = @_;
    $args = {} unless defined $args;

    die "You must provide a 'doc' argument to the constructor" unless $args->{doc};
    die "You must provide a 'repository' argument to the constructor" unless $args->{repository};

    if (my $doc = $args->{doc}){

        #Get the root element
        my $root = $doc->documentElement;

        #Register namespaces for searching purposes
        my $xpc = XML::LibXML::XPathContext->new();
        $xpc->registerNs('oai','http://www.openarchives.org/OAI/2.0/');

        my $xpath_identifier = XML::LibXML::XPathExpression->new("oai:header/oai:identifier");
        my $identifier = $xpc->findnodes($xpath_identifier,$root)->shift;
        $args->{header_identifier} = $identifier->textContent;

        my $xpath_datestamp = XML::LibXML::XPathExpression->new("oai:header/oai:datestamp");
        my $datestamp = $xpc->findnodes($xpath_datestamp,$root)->shift;
        $args->{header_datestamp} = $datestamp->textContent;

        my $xpath_status = XML::LibXML::XPathExpression->new(q{oai:header/@status});
        my $status_node = $xpc->findnodes($xpath_status,$root)->shift;
        $args->{header_status} = $status_node ? $status_node->textContent : "";
    }

    return bless ($args, $class);
}

=head2 is_deleted_upstream

    Returns true if OAI-PMH record is deleted upstream

=cut

sub is_deleted_upstream {
    my ($self, $args) = @_;
    if ($self->{header_status}){
        if ($self->{header_status} eq "deleted"){
            return 1;
        }
    }
    return 0;
}

=head2 set_filter

    $self->set_filter("/path/to/filter.xsl");

    Set a XSLT to use to filter records on import. This
    takes a full filepath as an argument.

=cut

sub set_filter {
    my ($self, $filter_definition) = @_;

    #Source a default XSLT to use for filtering
    my $htdocs  = C4::Context->config('intrahtdocs');
    my $theme   = C4::Context->preference("template");
    $self->{filter} = "$htdocs/$theme/en/xslt/StripOAIPMH.xsl";
    $self->{filter_type} = "xslt";

    if ($filter_definition && $filter_definition ne "default"){
        my ($filter_type, $filter) = $self->_parse_filter($filter_definition);
        if ($filter_type eq "xslt"){
            if (  -f $filter ){
                $self->{filter} = $filter;
                $self->{filter_type} = "xslt";
            }
        }
    }
}

sub _parse_filter {
    my ($self,$filter_definition) = @_;
    my ($type,$filter);
    my $filter_uri = URI->new($filter_definition);
    if ($filter_uri){
        my $scheme = $filter_uri->scheme;
        if ( ($scheme && $scheme eq "file") || ! $scheme ){
            my $path = $filter_uri->path;
            #Filters may theoretically be .xsl or .pm files
            my($filename, $dirs, $suffix) = fileparse($path,(".xsl",".pm"));
            if ($suffix){
                if ( $suffix eq ".xsl"){
                    $type = "xslt";
                    $filter = $path;
                }
            }
        }
    }
    return ($type,$filter);
}

=head2 filter

    Filters the OAI-PMH record using a filter

=cut

sub filter {
    my ($self) = @_;
    my $filtered = 0;
    my $doc = $self->{doc};
    my $filter = $self->{filter};
    my $filter_type = $self->{filter_type};
    if ($doc){
        if ($filter && -f $filter){
            if ($filter_type){
                if ( $filter_type eq 'xslt' ){
                    my $xslt = XML::LibXSLT->new();
                    my $style_doc = XML::LibXML->load_xml(location => $filter);
                    my $stylesheet = $xslt->parse_stylesheet($style_doc);
                    if ($stylesheet){
                        my $results = $stylesheet->transform($doc);
                        if ($results){
                            my $root = $results->documentElement;
                            if ($root){
                                my $namespace = $root->namespaceURI;
                                if ($namespace eq "http://www.loc.gov/MARC21/slim"){
                                    #NOTE: Both MARC21 and UNIMARC should be covered by this namespace
                                    my $marcxml = eval { Koha::OAI::Harvester::Import::MARCXML->new({ dom => $results, }) };
                                    if ($@){
                                        warn "Error Koha::OAI::Harvester::Import::MARCXML: $@";
                                        return;
                                    } else {
                                        return $marcxml;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    return;
}

sub _find_koha_link {
    my ($self, $args) = @_;
    my $record_type = $args->{record_type} // "biblio";
    my $link_id;
    if ($record_type eq "biblio"){
        my $link = Koha::OAI::Harvester::Biblios->new->find(
            {
                oai_repository => $self->{repository},
                oai_identifier => $self->{header_identifier},
            },
            { key => "oai_record",}
        );
        if ($link && $link->biblionumber){
            $link_id = $link->biblionumber;
        }
    }
    return $link_id;
}

=head2 import_record

    my ($action,$record_id) = $oai_record->import_record({
        filter => $filter,
        framework => $framework,
        record_type => $record_type,
        matcher => $matcher,
    });

    $action eq "added" || "updated" || "deleted" || "not_found" || "error"

=cut

sub import_record {
    my ($self, $args) = @_;
    my $filter = $args->{filter} || 'default';
    my $framework = $args->{framework} || '';
    my $record_type = $args->{record_type} || 'biblio';
    my $matcher = $args->{matcher};

    my $action = "error";

    #Find linkage between OAI-PMH repository-identifier and Koha record id
    my $linked_id = $self->_find_koha_link({
        record_type => $record_type,
    });

    if ($self->is_deleted_upstream){
        #NOTE: If a record is deleted upstream, it will not contain a metadata element
        if ($linked_id){
            $action = $self->delete_koha_record({
                record_id => $linked_id,
                record_type => $record_type,
            });
        }
        else {
            $action = "not_found";
            #NOTE: If there's no OAI-PMH repository-identifier pair in the database,
            #then there's no perfect way to find a linked record to delete.
        }
    }
    else {
        $self->set_filter($filter);


        my $import_record = $self->filter();

        if ($import_record){
            ($action,$linked_id) = $import_record->import_record({
                framework => $framework,
                record_type => $record_type,
                matcher => $matcher,
                koha_id => $linked_id,
            });

            if ($linked_id){
                #Link Koha record ID to OAI-PMH details for this record type,
                #if linkage doesn't already exist.
                $self->link_koha_record({
                    record_type => $record_type,
                    koha_id => $linked_id,
                });
            }
        }
    }

    #Log record details to database
    Koha::OAI::Harvester::History->new({
        header_identifier => $self->{header_identifier},
        header_datestamp => $self->{header_datestamp},
        header_status => $self->{header_status},
        record => $self->{doc}->toString(1),
        repository => $self->{repository},
        status => $action,
        filter => $filter,
        framework => $framework,
        record_type => $record_type,
        matcher_code => $matcher ? $matcher->code : undef,
    })->store();

    return ($action,$linked_id);
}

=head2 link_koha_record

    Link an OAI-PMH record with a Koha record using
    the OAI-PMH repository and OAI-PMH identifier

=cut

sub link_koha_record {
    my ($self, $args) = @_;
    my $record_type = $args->{record_type} // "biblio";
    my $koha_id = $args->{koha_id};
    if ($koha_id){
        if ($record_type eq "biblio"){
            my $import_oai_biblio = Koha::OAI::Harvester::Biblios->new->find_or_create({
                oai_repository => $self->{repository},
                oai_identifier => $self->{header_identifier},
                biblionumber => $koha_id,
            });
            if ( ! $import_oai_biblio->in_storage ){
                $import_oai_biblio->insert;
            }
        }
    }
}

=head2 delete_koha_record

    Delete a Koha record

=cut

sub delete_koha_record {
    my ($self, $args) = @_;
    my $record_type = $args->{record_type} // "biblio";
    my $record_id = $args->{record_id};

    my $action = "error";

    if ($record_type eq "biblio"){
        my $error = C4::Biblio::DelBiblio($record_id);
        if (!$error){
            $action = "deleted";
            #NOTE: If there's no error, a cascading database delete should
            #automatically remove the link between the Koha biblionumber and OAI-PMH record too
        }
    }
    return $action;
}

1;
