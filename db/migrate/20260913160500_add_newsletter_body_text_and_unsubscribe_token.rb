class AddNewsletterBodyTextAndUnsubscribeToken < ActiveRecord::Migration[8.1]
  def change
    # The plain-text twin of `body`, so both MIME parts of a sent issue are
    # archived exactly as delivered.
    add_column :newsletters, :body_text, :text

    # One-click unsubscribe requires a per-subscriber token that is safe to put
    # in a URL; the email address alone is not.
    add_column :subscribers, :unsubscribe_token, :string
    add_index :subscribers, :unsubscribe_token, unique: true

    # Backfill rows created before this column existed so every subscriber can
    # unsubscribe from day one.
    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE subscribers
          SET unsubscribe_token = lower(hex(randomblob(24)))
          WHERE unsubscribe_token IS NULL
        SQL
      end
    end
  end
end
