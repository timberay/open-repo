class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string   :email,       null: false
      t.boolean  :admin,       null: false, default: false
      t.bigint   :primary_identity_id  # FK added after identities table exists
      t.datetime :last_seen_at
      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
