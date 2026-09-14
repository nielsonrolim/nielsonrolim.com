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

ActiveRecord::Schema[8.1].define(version: 2026_09_14_150000) do
  create_table "categories", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index "lower(name)", name: "index_categories_on_lower_name", unique: true
  end

  create_table "clippings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "entry_id", null: false
    t.string "language"
    t.integer "newsletter_id"
    t.text "summary"
    t.string "summary_error"
    t.string "summary_status", default: "pending", null: false
    t.text "summary_translated"
    t.string "title", null: false
    t.string "title_translated"
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["entry_id"], name: "index_clippings_on_entry_id"
    t.index ["entry_id"], name: "index_clippings_on_unsent_entry", unique: true, where: "newsletter_id IS NULL"
    t.index ["newsletter_id"], name: "index_clippings_on_newsletter_id"
    t.index ["summary_status"], name: "index_clippings_on_summary_status"
  end

  create_table "data_migrations", primary_key: "version", id: :string, force: :cascade do |t|
  end

  create_table "entries", force: :cascade do |t|
    t.string "author"
    t.datetime "created_at", null: false
    t.integer "feed_id", null: false
    t.string "guid", null: false
    t.datetime "published_at"
    t.text "summary"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["feed_id", "guid"], name: "index_entries_on_feed_id_and_guid", unique: true
    t.index ["feed_id", "published_at"], name: "index_entries_on_feed_id_and_published_at"
    t.index ["feed_id"], name: "index_entries_on_feed_id"
    t.index ["published_at"], name: "index_entries_on_published_at"
    t.index ["url"], name: "index_entries_on_url"
  end

  create_table "feed_categories", force: :cascade do |t|
    t.integer "category_id", null: false
    t.datetime "created_at", null: false
    t.integer "feed_id", null: false
    t.datetime "updated_at", null: false
    t.index ["category_id"], name: "index_feed_categories_on_category_id"
    t.index ["feed_id", "category_id"], name: "index_feed_categories_on_feed_id_and_category_id", unique: true
    t.index ["feed_id"], name: "index_feed_categories_on_feed_id"
  end

  create_table "feeds", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "custom_title"
    t.text "description"
    t.string "last_error"
    t.datetime "last_fetched_at"
    t.string "site_url"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["last_fetched_at"], name: "index_feeds_on_last_fetched_at"
    t.index ["url"], name: "index_feeds_on_url", unique: true
  end

  create_table "newsletter_bodies", force: :cascade do |t|
    t.text "body", null: false
    t.text "body_text"
    t.datetime "created_at", null: false
    t.string "locale", null: false
    t.integer "newsletter_id", null: false
    t.string "subject", null: false
    t.datetime "updated_at", null: false
    t.index ["newsletter_id", "locale"], name: "index_newsletter_bodies_on_newsletter_id_and_locale", unique: true
    t.index ["newsletter_id"], name: "index_newsletter_bodies_on_newsletter_id"
  end

  create_table "newsletters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "recipient_count", default: 0, null: false
    t.datetime "sent_at"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["sent_at"], name: "index_newsletters_on_sent_at"
    t.index ["status"], name: "index_newsletters_on_status"
  end

  create_table "subscribers", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "language", default: "pt-BR", null: false
    t.string "unsubscribe_token"
    t.datetime "updated_at", null: false
    t.index "lower(email)", name: "index_subscribers_on_lower_email", unique: true
    t.index ["unsubscribe_token"], name: "index_subscribers_on_unsubscribe_token", unique: true
  end

  add_foreign_key "clippings", "entries"
  add_foreign_key "clippings", "newsletters"
  add_foreign_key "entries", "feeds"
  add_foreign_key "feed_categories", "categories"
  add_foreign_key "feed_categories", "feeds"
  add_foreign_key "newsletter_bodies", "newsletters"
end
