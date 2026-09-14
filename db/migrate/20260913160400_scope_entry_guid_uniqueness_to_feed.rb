class ScopeEntryGuidUniquenessToFeed < ActiveRecord::Migration[8.1]
  def change
    remove_index :entries, :guid
    # Two different feeds can legitimately reuse the same guid, so uniqueness
    # has to be scoped to the feed that owns the entry.
    add_index :entries, [ :feed_id, :guid ], unique: true
  end
end
