# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_01_215230) do
  create_table "blob_uploads", force: :cascade do |t|
    t.bigint "byte_offset", default: 0
    t.datetime "created_at", null: false
    t.integer "repository_id", null: false
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index [ "repository_id" ], name: "index_blob_uploads_on_repository_id"
    t.index [ "uuid" ], name: "index_blob_uploads_on_uuid", unique: true
  end

  create_table "blobs", force: :cascade do |t|
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "digest", null: false
    t.integer "references_count", default: 0
    t.bigint "size", null: false
    t.datetime "updated_at", null: false
    t.index [ "digest" ], name: "index_blobs_on_digest", unique: true
  end

  create_table "identities", force: :cascade do |t|
    t.string "avatar_url"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.boolean "email_verified"
    t.datetime "last_login_at"
    t.string "name"
    t.string "provider", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index [ "provider", "uid" ], name: "index_identities_on_provider_and_uid", unique: true
    t.index [ "user_id" ], name: "index_identities_on_user_id"
  end

  create_table "layers", force: :cascade do |t|
    t.integer "blob_id", null: false
    t.integer "manifest_id", null: false
    t.integer "position", null: false
    t.index [ "blob_id" ], name: "index_layers_on_blob_id"
    t.index [ "manifest_id", "blob_id" ], name: "index_layers_on_manifest_id_and_blob_id", unique: true
    t.index [ "manifest_id", "position" ], name: "index_layers_on_manifest_id_and_position", unique: true
    t.index [ "manifest_id" ], name: "index_layers_on_manifest_id"
  end

  create_table "manifests", force: :cascade do |t|
    t.string "architecture"
    t.string "config_digest"
    t.datetime "created_at", null: false
    t.string "digest", null: false
    t.text "docker_config"
    t.datetime "last_pulled_at"
    t.string "media_type", null: false
    t.string "os"
    t.text "payload", null: false
    t.integer "pull_count", default: 0
    t.integer "repository_id", null: false
    t.bigint "size", null: false
    t.datetime "updated_at", null: false
    t.index [ "digest" ], name: "index_manifests_on_digest", unique: true
    t.index [ "last_pulled_at" ], name: "index_manifests_on_last_pulled_at"
    t.index [ "repository_id", "digest" ], name: "index_manifests_on_repository_id_and_digest"
    t.index [ "repository_id" ], name: "index_manifests_on_repository_id"
  end

  create_table "personal_access_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.integer "identity_id", null: false
    t.string "kind", default: "cli", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.string "prefix", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index [ "identity_id", "name" ], name: "index_personal_access_tokens_on_identity_id_and_name", unique: true
    t.index [ "identity_id" ], name: "index_personal_access_tokens_on_identity_id"
    t.index [ "revoked_at" ], name: "index_personal_access_tokens_on_revoked_at"
    t.index [ "token_digest" ], name: "index_personal_access_tokens_on_token_digest", unique: true
  end

  create_table "pull_events", force: :cascade do |t|
    t.integer "manifest_id", null: false
    t.datetime "occurred_at", null: false
    t.string "remote_ip"
    t.integer "repository_id", null: false
    t.string "tag_name"
    t.string "user_agent"
    t.index [ "manifest_id", "occurred_at" ], name: "index_pull_events_on_manifest_id_and_occurred_at"
    t.index [ "manifest_id" ], name: "index_pull_events_on_manifest_id"
    t.index [ "occurred_at" ], name: "index_pull_events_on_occurred_at"
    t.index [ "repository_id", "occurred_at" ], name: "index_pull_events_on_repository_id_and_occurred_at"
    t.index [ "repository_id" ], name: "index_pull_events_on_repository_id"
  end

  create_table "repositories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "maintainer"
    t.string "name", null: false
    t.integer "owner_identity_id", null: false
    t.string "tag_protection_pattern"
    t.string "tag_protection_policy", default: "none", null: false
    t.integer "tags_count", default: 0
    t.bigint "total_size", default: 0
    t.datetime "updated_at", null: false
    t.index [ "name" ], name: "index_repositories_on_name", unique: true
    t.index [ "owner_identity_id" ], name: "index_repositories_on_owner_identity_id"
  end

  create_table "repository_members", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "identity_id", null: false
    t.integer "repository_id", null: false
    t.string "role", null: false
    t.index [ "identity_id", "role" ], name: "index_repository_members_on_identity_id_and_role"
    t.index [ "identity_id" ], name: "index_repository_members_on_identity_id"
    t.index [ "repository_id", "identity_id" ], name: "index_repository_members_on_repository_id_and_identity_id", unique: true
    t.index [ "repository_id" ], name: "index_repository_members_on_repository_id"
  end

  create_table "tag_events", force: :cascade do |t|
    t.string "action", null: false
    t.string "actor"
    t.integer "actor_identity_id"
    t.string "new_digest"
    t.datetime "occurred_at", null: false
    t.string "previous_digest"
    t.integer "repository_id", null: false
    t.string "tag_name", null: false
    t.index [ "actor_identity_id" ], name: "index_tag_events_on_actor_identity_id"
    t.index [ "occurred_at" ], name: "index_tag_events_on_occurred_at"
    t.index [ "repository_id", "tag_name" ], name: "index_tag_events_on_repository_id_and_tag_name"
    t.index [ "repository_id" ], name: "index_tag_events_on_repository_id"
  end

  create_table "tags", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "manifest_id", null: false
    t.string "name", null: false
    t.integer "repository_id", null: false
    t.datetime "updated_at", null: false
    t.index [ "manifest_id" ], name: "index_tags_on_manifest_id"
    t.index [ "repository_id", "name" ], name: "index_tags_on_repository_id_and_name", unique: true
    t.index [ "repository_id" ], name: "index_tags_on_repository_id"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "last_seen_at"
    t.bigint "primary_identity_id"
    t.datetime "updated_at", null: false
    t.index [ "email" ], name: "index_users_on_email", unique: true
    t.index [ "primary_identity_id" ], name: "index_users_on_primary_identity_id"
  end

  add_foreign_key "blob_uploads", "repositories"
  add_foreign_key "identities", "users", on_delete: :restrict
  add_foreign_key "layers", "blobs"
  add_foreign_key "layers", "manifests"
  add_foreign_key "manifests", "repositories"
  add_foreign_key "personal_access_tokens", "identities", on_delete: :cascade
  add_foreign_key "pull_events", "manifests"
  add_foreign_key "pull_events", "repositories"
  add_foreign_key "repositories", "identities", column: "owner_identity_id", on_delete: :restrict
  add_foreign_key "repository_members", "identities", on_delete: :cascade
  add_foreign_key "repository_members", "repositories", on_delete: :cascade
  add_foreign_key "tag_events", "identities", column: "actor_identity_id", on_delete: :nullify
  add_foreign_key "tag_events", "repositories"
  add_foreign_key "tags", "manifests"
  add_foreign_key "tags", "repositories"
  add_foreign_key "users", "identities", column: "primary_identity_id", on_delete: :nullify
end
