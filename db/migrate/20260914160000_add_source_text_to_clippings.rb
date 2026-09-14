class AddSourceTextToClippings < ActiveRecord::Migration[8.1]
  # A clipping can now be added by hand from a URL, with no entry behind it, and
  # keeps the article text that was fetched (or pasted) as the source the summary
  # is generated from.
  def change
    change_column_null :clippings, :entry_id, true
    add_column :clippings, :source_text, :text
  end
end
