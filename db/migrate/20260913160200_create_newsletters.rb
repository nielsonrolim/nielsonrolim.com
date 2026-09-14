class CreateNewsletters < ActiveRecord::Migration[8.1]
  def change
    create_table :newsletters do |t|
      t.string :subject, null: false
      t.text :body, null: false
      t.string :status, null: false, default: "draft"
      t.datetime :sent_at
      t.integer :recipient_count, null: false, default: 0

      t.timestamps
    end

    add_index :newsletters, :status
    add_index :newsletters, :sent_at
  end
end
