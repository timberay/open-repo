class CreateRepositoryMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :repository_members do |t|
      t.references :repository, null: false, foreign_key: { on_delete: :cascade }
      t.references :identity,   null: false, foreign_key: { on_delete: :cascade }
      t.string :role, null: false  # "writer" | "admin"
      t.datetime :created_at, null: false
    end

    add_index :repository_members, [ :repository_id, :identity_id ], unique: true
    add_index :repository_members, [ :identity_id, :role ]
  end
end
