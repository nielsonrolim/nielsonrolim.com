class BackfillSourceNameOnClippings < ActiveRecord::Migration[8.1]
  # Manual clippings added before source_name existed get it now, derived from
  # the URL the same way new ones are: the channel for a YouTube video, the
  # site domain otherwise. Best effort — a clipping that cannot be resolved is
  # left as it was rather than breaking the migration.
  def up
    Clipping.reset_column_information

    Clipping.where(entry_id: nil, source_name: nil).find_each do |clipping|
      clipping.update_column(:source_name, SourceNameResolver.new.call(clipping.url))
    rescue StandardError
      # Best effort: the next one still gets its chance.
    end
  end

  def down
    # No way to tell a backfilled source from one stored at creation.
  end
end
