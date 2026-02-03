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

ActiveRecord::Schema[8.1].define(version: 2026_02_03_010727) do
  create_table "registries", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "is_active", default: true, null: false
    t.boolean "is_default", default: false, null: false
    t.datetime "last_connected_at"
    t.string "name", null: false
    t.string "password_digest"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.string "username"
    t.index ["is_default"], name: "index_registries_on_is_default"
    t.index ["name"], name: "index_registries_on_name", unique: true
    t.index ["url"], name: "index_registries_on_url"
  end
end
