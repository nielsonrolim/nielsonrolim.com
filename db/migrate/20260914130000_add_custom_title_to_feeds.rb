class AddCustomTitleToFeeds < ActiveRecord::Migration[8.1]
  # The feed's own title keeps being refreshed from the feed on every poll.
  # `custom_title` is the user's override, used for display when present, so
  # editing a title never fights the fetcher.
  def up
    add_column :feeds, :custom_title, :string
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
