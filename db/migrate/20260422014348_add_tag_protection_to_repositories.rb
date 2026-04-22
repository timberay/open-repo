class AddTagProtectionToRepositories < ActiveRecord::Migration[8.1]
  # Rolling this migration back drops `tag_protection_policy` and
  # `tag_protection_pattern`. Without the `down` guard below this would
  # silently delete every repo's configured protection policy during a
  # `db:rollback`. The guard permits rollback only when all policies are
  # still at the default `"none"` (i.e., nothing would be lost).
  def up
    add_column :repositories, :tag_protection_policy, :string, null: false, default: "none"
    add_column :repositories, :tag_protection_pattern, :string
  end

  def down
    non_default = select_value(
      "SELECT COUNT(*) FROM repositories WHERE tag_protection_policy != 'none'"
    ).to_i

    if non_default.positive?
      raise ActiveRecord::IrreversibleMigration, <<~MSG.squish
        Rolling back would permanently drop non-default tag_protection_policy
        values from #{non_default} #{'repository'.pluralize(non_default)}.
        Export or reset first:
          Repository.update_all(tag_protection_policy: 'none', tag_protection_pattern: nil)
        then re-run `bin/rails db:rollback`.
      MSG
    end

    remove_column :repositories, :tag_protection_pattern
    remove_column :repositories, :tag_protection_policy
  end
end
