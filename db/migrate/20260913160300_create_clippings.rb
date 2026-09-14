class CreateClippings < ActiveRecord::Migration[8.1]
  def change
    create_table :clippings do |t|
      t.references :entry, null: false, foreign_key: true
      t.references :newsletter, foreign_key: true
      t.string :title, null: false
      t.string :url, null: false
      t.text :summary
      t.string :summary_status, null: false, default: "pending"
      t.string :summary_error

      t.timestamps
    end

    add_index :clippings, :summary_status
    # A unique index on entry_id would not stop duplicates once a clipping has been
    # sent (newsletter_id set), and SQLite ignores NULLs in unique indexes — so scope
    # uniqueness to the not-yet-sent clippings with a partial index.
    add_index :clippings, :entry_id, unique: true, where: "newsletter_id IS NULL",
              name: "index_clippings_on_unsent_entry"
  end
end
