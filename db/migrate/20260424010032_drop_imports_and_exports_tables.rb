class DropImportsAndExportsTables < ActiveRecord::Migration[8.1]
  def change
    drop_table :exports do |t|
      t.references :repository, null: false, foreign_key: true
      t.string :tag_name, null: false
      t.string :status, null: false, default: "pending"
      t.string :output_path
      t.text :error_message
      t.timestamps
    end

    drop_table :imports do |t|
      t.string :status, null: false, default: "pending"
      t.string :repository_name
      t.string :tag_name
      t.string :tar_path
      t.text :error_message
      t.integer :progress, default: 0
      t.timestamps
    end
  end
end
