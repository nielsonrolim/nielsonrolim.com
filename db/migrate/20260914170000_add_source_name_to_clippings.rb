class AddSourceNameToClippings < ActiveRecord::Migration[8.1]
  # A clipping added by hand has no feed behind it, so the publication or
  # channel it came from (a site domain, a YouTube channel) is stored here at
  # creation time and shown where feed clippings show the feed title.
  def change
    add_column :clippings, :source_name, :string
  end
end
