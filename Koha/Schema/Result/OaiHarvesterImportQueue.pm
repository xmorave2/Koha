use utf8;
package Koha::Schema::Result::OaiHarvesterImportQueue;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::OaiHarvesterImportQueue

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<oai_harvester_import_queue>

=cut

__PACKAGE__->table("oai_harvester_import_queue");

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

=head2 status

  data_type: 'varchar'
  default_value: 'new'
  is_nullable: 0
  size: 45

=head2 result

  data_type: 'text'
  is_nullable: 0

=head2 result_timestamp

  data_type: 'timestamp'
  datetime_undef_if_invalid: 1
  default_value: current_timestamp
  is_nullable: 0

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
  "status",
  {
    data_type => "varchar",
    default_value => "new",
    is_nullable => 0,
    size => 45,
  },
  "result",
  { data_type => "text", is_nullable => 0 },
  "result_timestamp",
  {
    data_type => "timestamp",
    datetime_undef_if_invalid => 1,
    default_value => \"current_timestamp",
    is_nullable => 0,
  },
);

=head1 PRIMARY KEY

=over 4

=item * L</id>

=back

=cut

__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07046 @ 2017-03-29 12:23:43
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:zBD+hMawbvu7sonuLRHnCA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
