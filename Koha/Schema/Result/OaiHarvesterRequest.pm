use utf8;
package Koha::Schema::Result::OaiHarvesterRequest;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::OaiHarvesterRequest

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<oai_harvester_requests>

=cut

__PACKAGE__->table("oai_harvester_requests");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 uuid

  data_type: 'varchar'
  is_nullable: 0
  size: 45

=head2 oai_verb

  data_type: 'varchar'
  is_nullable: 0
  size: 45

=head2 oai_metadataPrefix

  accessor: 'oai_metadata_prefix'
  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 oai_identifier

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 oai_from

  data_type: 'varchar'
  is_nullable: 1
  size: 45

=head2 oai_until

  data_type: 'varchar'
  is_nullable: 1
  size: 45

=head2 oai_set

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 http_url

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 http_username

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 http_password

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 http_realm

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 import_filter

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 import_framework_code

  data_type: 'varchar'
  is_nullable: 0
  size: 4

=head2 import_record_type

  data_type: 'enum'
  extra: {list => ["biblio","auth","holdings"]}
  is_nullable: 0

=head2 import_matcher_code

  data_type: 'varchar'
  is_nullable: 1
  size: 10

=head2 interval

  data_type: 'integer'
  extra: {unsigned => 1}
  is_nullable: 0

=head2 name

  data_type: 'varchar'
  is_nullable: 0
  size: 45

=cut

__PACKAGE__->add_columns(
  "id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "uuid",
  { data_type => "varchar", is_nullable => 0, size => 45 },
  "oai_verb",
  { data_type => "varchar", is_nullable => 0, size => 45 },
  "oai_metadataPrefix",
  {
    accessor => "oai_metadata_prefix",
    data_type => "varchar",
    is_nullable => 0,
    size => 255,
  },
  "oai_identifier",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "oai_from",
  { data_type => "varchar", is_nullable => 1, size => 45 },
  "oai_until",
  { data_type => "varchar", is_nullable => 1, size => 45 },
  "oai_set",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "http_url",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "http_username",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "http_password",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "http_realm",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "import_filter",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "import_framework_code",
  { data_type => "varchar", is_nullable => 0, size => 4 },
  "import_record_type",
  {
    data_type => "enum",
    extra => { list => ["biblio", "auth", "holdings"] },
    is_nullable => 0,
  },
  "import_matcher_code",
  { data_type => "varchar", is_nullable => 1, size => 10 },
  "interval",
  { data_type => "integer", extra => { unsigned => 1 }, is_nullable => 0 },
  "name",
  { data_type => "varchar", is_nullable => 0, size => 45 },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07046 @ 2017-04-07 11:26:24
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:Vm/b4yurmr8WF7z+Fo6KEw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
