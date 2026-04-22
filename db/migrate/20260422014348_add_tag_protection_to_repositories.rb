class AddTagProtectionToRepositories < ActiveRecord::Migration[8.1]
  # Rolling this migration back drops `tag_protection_policy` and
  # `tag_protection_pattern`, which PERMANENTLY discards every repo's
  # configured protection policy. See TODOS.md P3 entry for a safer
  # `IrreversibleMigration` guard to add once this feature is live.
  def change
    add_column :repositories, :tag_protection_policy, :string, null: false, default: "none"
    add_column :repositories, :tag_protection_pattern, :string
  end
end
