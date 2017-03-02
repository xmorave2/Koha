use utf8;
package Koha::Schema::Result::OaiHarvesterBiblio;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

=head1 NAME

Koha::Schema::Result::OaiHarvesterBiblio

=cut

use strict;
use warnings;

use base 'DBIx::Class::Core';

=head1 TABLE: C<oai_harvester_biblios>

=cut

__PACKAGE__->table("oai_harvester_biblios");

=head1 ACCESSORS

=head2 import_oai_biblio_id

  data_type: 'integer'
  extra: {unsigned => 1}
  is_auto_increment: 1
  is_nullable: 0

=head2 oai_repository

  data_type: 'varchar'
  is_nullable: 0
  size: 255

=head2 oai_identifier

  data_type: 'varchar'
  is_nullable: 1
  size: 255

=head2 biblionumber

  data_type: 'integer'
  is_foreign_key: 1
  is_nullable: 0

=cut

__PACKAGE__->add_columns(
  "import_oai_biblio_id",
  {
    data_type => "integer",
    extra => { unsigned => 1 },
    is_auto_increment => 1,
    is_nullable => 0,
  },
  "oai_repository",
  { data_type => "varchar", is_nullable => 0, size => 255 },
  "oai_identifier",
  { data_type => "varchar", is_nullable => 1, size => 255 },
  "biblionumber",
  { data_type => "integer", is_foreign_key => 1, is_nullable => 0 },
);

=head1 PRIMARY KEY

=over 4

=item * L</import_oai_biblio_id>

=back

=cut

__PACKAGE__->set_primary_key("import_oai_biblio_id");

=head1 UNIQUE CONSTRAINTS

=head2 C<oai_record>

=over 4

=item * L</oai_identifier>

=item * L</oai_repository>

=back

=cut

__PACKAGE__->add_unique_constraint("oai_record", ["oai_identifier", "oai_repository"]);

=head1 RELATIONS

=head2 biblionumber

Type: belongs_to

Related object: L<Koha::Schema::Result::Biblio>

=cut

__PACKAGE__->belongs_to(
  "biblionumber",
  "Koha::Schema::Result::Biblio",
  { biblionumber => "biblionumber" },
  { is_deferrable => 1, on_delete => "CASCADE", on_update => "NO ACTION" },
);


# Created by DBIx::Class::Schema::Loader v0.07046 @ 2017-03-29 12:23:43
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:2URn8tPABMKC+JuIMfGeYw


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
