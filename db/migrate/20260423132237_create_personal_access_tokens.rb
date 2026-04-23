class CreatePersonalAccessTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :personal_access_tokens do |t|
      t.references :identity, null: false, foreign_key: { on_delete: :cascade }
      t.string   :name,         null: false
      t.string   :token_digest, null: false
      t.string   :kind,         null: false, default: "cli"
      t.datetime :last_used_at
      t.datetime :expires_at
      t.datetime :revoked_at
      t.timestamps
    end
    add_index :personal_access_tokens, :token_digest, unique: true
    add_index :personal_access_tokens, [ :identity_id, :name ], unique: true
    add_index :personal_access_tokens, :revoked_at
  end
end
