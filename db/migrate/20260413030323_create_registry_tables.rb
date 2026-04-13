class CreateRegistryTables < ActiveRecord::Migration[8.1]
  def change
    create_table :repositories do |t|
      t.string :name, null: false
      t.text :description
      t.string :maintainer
      t.integer :tags_count, default: 0
      t.bigint :total_size, default: 0
      t.timestamps
      t.index :name, unique: true
    end

    create_table :manifests do |t|
      t.references :repository, null: false, foreign_key: true
      t.string :digest, null: false
      t.string :media_type, null: false
      t.text :payload, null: false
      t.bigint :size, null: false
      t.string :config_digest
      t.string :architecture
      t.string :os
      t.text :docker_config
      t.integer :pull_count, default: 0
      t.datetime :last_pulled_at
      t.timestamps
      t.index :digest, unique: true
      t.index [:repository_id, :digest]
      t.index :last_pulled_at
    end

    create_table :tags do |t|
      t.references :repository, null: false, foreign_key: true
      t.references :manifest, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
      t.index [:repository_id, :name], unique: true
    end

    create_table :blobs do |t|
      t.string :digest, null: false
      t.bigint :size, null: false
      t.string :content_type
      t.integer :references_count, default: 0
      t.timestamps
      t.index :digest, unique: true
    end

    create_table :layers do |t|
      t.references :manifest, null: false, foreign_key: true
      t.references :blob, null: false, foreign_key: true
      t.integer :position, null: false
      t.index [:manifest_id, :position], unique: true
      t.index [:manifest_id, :blob_id], unique: true
    end

    create_table :blob_uploads do |t|
      t.references :repository, null: false, foreign_key: true
      t.string :uuid, null: false
      t.bigint :byte_offset, default: 0
      t.timestamps
      t.index :uuid, unique: true
    end

    create_table :tag_events do |t|
      t.references :repository, null: false, foreign_key: true
      t.string :tag_name, null: false
      t.string :action, null: false
      t.string :previous_digest
      t.string :new_digest
      t.string :actor
      t.datetime :occurred_at, null: false
      t.index [:repository_id, :tag_name]
      t.index :occurred_at
    end

    create_table :pull_events do |t|
      t.references :manifest, null: false, foreign_key: true
      t.references :repository, null: false, foreign_key: true
      t.string :tag_name
      t.string :user_agent
      t.string :remote_ip
      t.datetime :occurred_at, null: false
      t.index [:repository_id, :occurred_at]
      t.index [:manifest_id, :occurred_at]
      t.index :occurred_at
    end

    create_table :imports do |t|
      t.string :status, null: false, default: 'pending'
      t.string :repository_name
      t.string :tag_name
      t.string :tar_path
      t.text :error_message
      t.integer :progress, default: 0
      t.timestamps
    end

    create_table :exports do |t|
      t.references :repository, null: false, foreign_key: true
      t.string :tag_name, null: false
      t.string :status, null: false, default: 'pending'
      t.string :output_path
      t.text :error_message
      t.timestamps
    end
  end
end
