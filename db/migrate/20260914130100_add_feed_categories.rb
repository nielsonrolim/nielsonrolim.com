class AddFeedCategories < ActiveRecord::Migration[8.1]
  # Replaces the single `feeds.category` string with a real many-to-many:
  # existing values are turned into categories (case-insensitively) and joined,
  # then the column is dropped. Irreversible on purpose — rolling back would
  # have to guess which of a feed's categories was "the" one.
  def up
    create_table :categories do |t|
      t.string :name, null: false

      t.timestamps
    end
    add_index :categories, "lower(name)", unique: true, name: "index_categories_on_lower_name"

    create_table :feed_categories do |t|
      t.references :feed, null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true

      t.timestamps
    end
    add_index :feed_categories, [ :feed_id, :category_id ], unique: true

    # Backfill in SQL rather than through the Feed model: by the time this runs
    # the model only knows the association, not the column being read here.
    execute <<~SQL.squish
      INSERT INTO categories (name, created_at, updated_at)
      SELECT DISTINCT TRIM(category), CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM feeds
      WHERE category IS NOT NULL AND TRIM(category) <> ''
    SQL

    execute <<~SQL.squish
      INSERT INTO feed_categories (feed_id, category_id, created_at, updated_at)
      SELECT feeds.id, categories.id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM feeds
      JOIN categories ON lower(categories.name) = lower(TRIM(feeds.category))
      WHERE feeds.category IS NOT NULL AND TRIM(feeds.category) <> ''
    SQL

    remove_column :feeds, :category
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
