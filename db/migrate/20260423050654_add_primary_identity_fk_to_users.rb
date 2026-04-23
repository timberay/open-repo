class AddPrimaryIdentityFkToUsers < ActiveRecord::Migration[8.1]
  def change
    add_foreign_key :users, :identities, column: :primary_identity_id, on_delete: :nullify
    add_index :users, :primary_identity_id
  end
end
