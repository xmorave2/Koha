use utf8;
package Koha::Schema::Result::OaiHarvesterHistory;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::OaiHarvesterHistory

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<oai_harvester_history>

=cut

__PACKAGE__->table("oai_harvester_history");

=head1 ACCESSORS

=head2 import_oai_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 repository

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 header_identifier

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 header_datestamp

  data_type: 'datetime'
  datetime_undef_if_invalid: 1
  is_nullable: 0

=head2 header_status

  data_type: 'varchar'
  is_nullable: 1
  size: 45

=head2 record

  data_type: 'longtext'
  is_nullable: 0

=head2 upload_timestamp

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
  is_nullable: 0

=head2 status

  data_type: 'varchar'
  is_nullable: 0
  size: 45

=head2 filter

  data_type: 'text'
  is_nullable: 0

=head2 framework

  data_type: 'varchar'
  is_nullable: 0
  size: 4

=head2 record_type

  data_type: 'enum'
  extra: {list => ["biblio","auth","holdings"]}
  is_nullable: 0

=head2 matcher_code

  data_type: 'varchar'
  is_nullable: 1
  size: 10

=cut

__PACKAGE__->add_columns(
  "import_oai_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "repository",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "header_identifier",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "header_datestamp",
  {
    data_type => "datetime",
    datetime_undef_if_invalid => 1,
    is_nullable => 0,
  },
  "header_status",
  { data_type => "varchar", is_nullable => 1, size => 45 },
  "record",
  { data_type => "longtext", is_nullable => 0 },
  "upload_timestamp",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 0,
  },
  "status",
  { data_type => "varchar", is_nullable => 0, size => 45 },
  "filter",
  { data_type => "text", is_nullable => 0 },
  "framework",
  { data_type => "varchar", is_nullable => 0, size => 4 },
  "record_type",
  {
    data_type => "enum",
    extra => { list => ["biblio", "auth", "holdings"] },
    is_nullable => 0,
  },
  "matcher_code",
  { data_type => "varchar", is_nullable => 1, size => 10 },
);

=head1 PRIMARY KEY

=over 4

=item * L</import_oai_id>

=back

=cut

__PACKAGE__->set_primary_key("import_oai_id");


# Created by DBIx::Class::Schema::Loader v0.07042 @ 2018-10-31 05:53:48
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:C/ETSPdx0O4xfQnu09kGeQ


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
