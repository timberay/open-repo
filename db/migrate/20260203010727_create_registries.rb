class CreateRegistries < ActiveRecord::Migration[8.1]
  def change
    create_table :registries do |t|
      t.string :name, null: false
      t.string :url, null: false
      t.string :username
      t.string :password_digest
      t.boolean :is_default, default: false, null: false
      t.boolean :is_active, default: true, null: false
      t.datetime :last_connected_at

      t.timestamps
    end

    add_index :registries, :name, unique: true
    add_index :registries, :url
    add_index :registries, :is_default
  end
end
