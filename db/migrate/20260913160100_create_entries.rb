class CreateEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :entries do |t|
      t.references :feed, null: false, foreign_key: true
      t.string :title, null: false
      t.string :url, null: false
      t.string :author
      t.string :guid, null: false
      t.text :summary
      t.datetime :published_at

      t.timestamps
    end

    add_index :entries, :guid, unique: true
    add_index :entries, :url
    add_index :entries, :published_at
    add_index :entries, [ :feed_id, :published_at ]
  end
end
