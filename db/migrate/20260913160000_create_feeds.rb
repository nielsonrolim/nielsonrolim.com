class CreateFeeds < ActiveRecord::Migration[8.1]
  def change
    create_table :feeds do |t|
      t.string :title, null: false
      t.string :url, null: false
      t.string :site_url
      t.text :description
      t.string :category
      t.datetime :last_fetched_at
      t.string :last_error

      t.timestamps
    end

    add_index :feeds, :url, unique: true
    add_index :feeds, :last_fetched_at
  end
end
