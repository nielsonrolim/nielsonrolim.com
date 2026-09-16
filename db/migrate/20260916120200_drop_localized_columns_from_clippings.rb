class DropLocalizedColumnsFromClippings < ActiveRecord::Migration[8.1]
  # The language-specific content now lives on clipping_variants; the clipping
  # only keeps what identifies the story and the source it was summarized from.
  def up
    remove_column :clippings, :title
    remove_column :clippings, :url
    remove_column :clippings, :summary
    remove_column :clippings, :title_translated
    remove_column :clippings, :summary_translated
  end

  def down
    add_column :clippings, :title, :string, null: false, default: ""
    add_column :clippings, :url, :string, null: false, default: ""
    add_column :clippings, :summary, :text
    add_column :clippings, :title_translated, :string
    add_column :clippings, :summary_translated, :text
  end
end
