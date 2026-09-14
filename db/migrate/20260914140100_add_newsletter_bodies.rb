class AddNewsletterBodies < ActiveRecord::Migration[8.1]
  # An issue now carries one rendered version per language, so a subscriber can
  # receive it in theirs. Issues sent before this only exist in the app's default
  # language, which is what the backfill records. Irreversible: the split cannot
  # be undone without guessing which language was "the" one.
  def up
    create_table :newsletter_bodies do |t|
      t.references :newsletter, null: false, foreign_key: true
      t.string :locale, null: false
      t.string :subject, null: false
      t.text :body, null: false
      t.text :body_text

      t.timestamps
    end
    add_index :newsletter_bodies, [ :newsletter_id, :locale ], unique: true

    execute <<~SQL.squish
      INSERT INTO newsletter_bodies (newsletter_id, locale, subject, body, body_text, created_at, updated_at)
      SELECT id, 'pt-BR', subject, body, body_text, created_at, updated_at
      FROM newsletters
    SQL

    remove_column :newsletters, :subject
    remove_column :newsletters, :body
    remove_column :newsletters, :body_text
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
