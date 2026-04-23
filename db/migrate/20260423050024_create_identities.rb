class CreateIdentities < ActiveRecord::Migration[8.1]
  def change
    create_table :identities do |t|
      t.references :user, null: false, foreign_key: { on_delete: :restrict }
      t.string   :provider,       null: false
      t.string   :uid,            null: false
      t.string   :email,          null: false
      t.boolean  :email_verified
      t.string   :name
      t.string   :avatar_url
      t.datetime :last_login_at
      t.timestamps
    end
    add_index :identities, [ :provider, :uid ], unique: true
  end
end
