package Koha::OAI::Harvester::Import::MARCXML;

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
use MARC::Record;

use C4::Context;
use C4::Biblio;

use constant MAX_MATCHES => 99999; #NOTE: This is an arbitrary value. We want to get all matches.

=head1 NAME

Koha::OAI::Harvester::Import::MARCXML

=head1 SYNOPSIS

    use Koha::OAI::Harvester::Import::MARCXML;
    my $marcxml = eval { Koha::OAI::Harvester::Import::MARCXML->new({ dom => $results, }) };

=head1 METHODS

=head2 new

    Create object

=cut

sub new {
    my ($class, $args) = @_;
    $args = {} unless defined $args;
    if ( (! $args->{dom}) && (! $args->{marc_record}) ){
        die "You must provide either a dom or marc_record argument to this constructor";
    }
    if ( $args->{dom} && ( ! $args->{marc_record} ) ){
        my $dom = $args->{dom};
        my $xml = $dom->toString(2);
        my $marcflavour = C4::Context->preference('marcflavour') || 'MARC21';
        my $marc_record = eval {MARC::Record::new_from_xml( $xml, "utf8", $marcflavour)};
        if ($@){
            die "Unable to create MARC::Record object";
        }
        if ($marc_record){
            $args->{marc_record} = $marc_record;
        }
    }
    return bless ($args, $class);
}

=head2 import_record

    Import a record into Koha

=cut

sub import_record {
    my ($self,$args) = @_;
    my $framework = $args->{framework};
    my $record_type = $args->{record_type};
    my $matcher = $args->{matcher};
    my $koha_id = $args->{koha_id};

    my $action = "error";

    #Try to find a matching Koha MARCXML record via Zebra
    if (! $koha_id && $matcher){
        my $matched_id = $self->_try_matcher({
            matcher => $matcher,
        });
        if ($matched_id){
            $koha_id = $matched_id;
        }
    }

    if ($koha_id){
        #Update
        ($action) = $self->_mod_koha_record({
            record_type => $record_type,
            framework => $framework,
            koha_id => $koha_id,
        });
    }
    else {
        #Add
        ($action,$koha_id) = $self->_add_koha_record({
            record_type => $record_type,
            framework => $framework,
        });
    }

    return ($action,$koha_id);
}

sub _try_matcher {
    my ($self, $args) = @_;
    my $marc_record = $self->{marc_record};
    my $matcher = $args->{matcher};
    my $matched_id;
    my @matches = $matcher->get_matches($marc_record, MAX_MATCHES);
    if (@matches){
        my $bestrecordmatch = shift @matches;
        if ($bestrecordmatch && $bestrecordmatch->{record_id}){
            $matched_id = $bestrecordmatch->{record_id};
        }
    }
    return $matched_id;
}

sub _add_koha_record {
    my ($self, $args) = @_;
    my $marc_record = $self->{marc_record};
    my $record_type = $args->{record_type} // "biblio";
    my $framework = $args->{framework};
    my $koha_id;
    my $action = "error";
    if ($record_type eq "biblio"){
        #NOTE: Strip item fields to prevent any accidentally getting through.
        C4::Biblio::_strip_item_fields($marc_record,$framework);
        my ($biblionumber,$biblioitemnumber) = C4::Biblio::AddBiblio($marc_record,$framework);
        if ($biblionumber){
            $action = "added";
            $koha_id = $biblionumber;
        }
    }
    return ($action,$koha_id);
}

sub _mod_koha_record {
    my ($self, $args) = @_;
    my $marc_record = $self->{marc_record};
    my $record_type = $args->{record_type} // "biblio";
    my $framework = $args->{framework};
    my $koha_id = $args->{koha_id};
    my $action = "error";
    if ($record_type eq "biblio"){
        #NOTE: Strip item fields to prevent any accidentally getting through.
        C4::Biblio::_strip_item_fields($marc_record,$framework);
        my $updated = C4::Biblio::ModBiblio($marc_record, $koha_id, $framework);
        if ($updated){
            $action = "updated";
        }
    }
    return ($action);
}

1;
