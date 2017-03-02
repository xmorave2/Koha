package Koha::OAI::Harvester::Request;

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

use Carp;

use base qw(Koha::Object);

#For validation
use URI;
use HTTP::OAI;

=head1 NAME

Koha::OAI::Harvester::Request -

=head1 API

=head2 Class Methods

=cut



=head3 _type

=cut

sub _type {
    return 'OaiHarvesterRequest';
}

sub validate {
    my ($self) = @_;
    my $errors = {};

    #Step one: validate URL
    my $uri = URI->new($self->http_url);
    if ( $uri && $uri->scheme && ($uri->scheme eq "http" || $uri->scheme eq "https") ){

        #Step two: validate access and authorization to URL
        my $harvester = $self->_harvester();
        my $identify = $harvester->Identify;
        if ($identify->is_success){

            #Step three: validate OAI-PMH parameters

            #Test Set
            my $set = $self->oai_set;
            if ($set){
                my $set_response = $harvester->ListSets();
                my @server_sets = $set_response->set;
                if ( ! grep {$_->setSpec eq $set} @server_sets ){
                    $errors->{oai_set}->{unavailable} = 1;
                }
            }

            #Test Metadata Prefix
            my $metadataPrefix = $self->oai_metadataPrefix;
            if ($metadataPrefix){
                my $metadata_response = $harvester->ListMetadataFormats();
                my @server_formats = $metadata_response->metadataFormat;
                if ( ! grep { $_->metadataPrefix eq $metadataPrefix } @server_formats ){
                    $errors->{oai_metadataPrefix}->{unavailable} = 1;
                }
            }
            else {
                $errors->{oai_metadataPrefix}->{missing} = 1;
            }

            #Test Granularity and Timestamps
            my $server_granularity = $identify->granularity;
            my $from = $self->oai_from;
            my $until = $self->oai_until;
            if ($from || $until){
                my ($from_granularity,$until_granularity);
                if ($from){
                    $from_granularity = _determine_granularity($from);
                    if ($from_granularity eq "YYYY-MM-DDThh:mm:ssZ"){
                        $errors->{oai_from}->{unavailable} = 1 if $server_granularity ne $from_granularity;
                    } elsif ($from_granularity eq "failed"){
                        $errors->{oai_from}->{malformed} = 1;
                    }
                }
                if ($until){
                    $until_granularity = _determine_granularity($until);
                    if ($until_granularity eq "YYYY-MM-DDThh:mm:ssZ"){
                        $errors->{oai_until}->{unavailable} = 1 if $server_granularity ne $until_granularity;
                    } elsif ($until_granularity eq "failed"){
                        $errors->{oai_until}->{malformed} = 1;
                    }
                }
                if ($from && $until){
                    if ($from_granularity ne $until_granularity){
                        $errors->{oai}->{granularity_mismatch} = 1;
                    }
                }
            }

            #Test if identifier is provided when using GetRecord
            my $verb = $self->oai_verb;
            if ($verb && $verb eq "GetRecord"){
                my $identifier = $self->oai_identifier;
                if (! $identifier){
                    $errors->{oai_identifier}->{missing} = 1;
                }
            }
        }
        elsif ($identify->is_error){
            foreach my $error ($identify->errors){
                if ($error->code =~ /^404$/){
                    $errors->{http}->{404} = 1;
                } elsif ($error->code =~ /^401$/){
                    $errors->{http}->{401} = 1;
                } else {
                    $errors->{http}->{generic} = 1;
                }
            }
        }
        else {
            $errors->{http}->{generic} = 1;
        }
    } else {
        $errors->{http_url}->{malformed} = 1;
    }
    return $errors;
}

sub _harvester {
    my ( $self ) = @_;
    my $harvester;
    if ($self->http_url){
        $harvester = new HTTP::OAI::Harvester( baseURL => $self->http_url );
        my $uri = URI->new($self->http_url);
        if ($uri->scheme && ($uri->scheme eq 'http' || $uri->scheme eq 'https') ){
            my $host = $uri->host;
            my $port = $uri->port;
            $harvester->credentials($host.":".$port, $self->http_realm, $self->http_username, $self->http_password);
        }
    }
    return $harvester;
}

sub _determine_granularity {
    my ($timestamp) = @_;
    my $granularity;
    if ($timestamp =~ /^(\d{4}-\d{2}-\d{2})(T\d{2}:\d{2}:\d{2}Z)?$/){
        if ($1 && $2){
            $granularity = "YYYY-MM-DDThh:mm:ssZ";
        } elsif ($1 && !$2){
            $granularity = "YYYY-MM-DD";
        } else {
            $granularity = "failed";
        }
    } else {
        $granularity = "failed";
    }
    return $granularity;
}

=head1 AUTHOR

David Cook <dcook@prosentient.com.au>

=cut

1;
