class AddLanguageToSubscribers < ActiveRecord::Migration[8.1]
  # The language picked on the site at signup, so an issue can go out in the
  # reader's language. The default backfills everyone who subscribed before the
  # column existed (SQLite fills existing rows with the column default).
  def up
    add_column :subscribers, :language, :string, null: false, default: "pt-BR"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
