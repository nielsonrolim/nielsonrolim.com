class AddDeferredAtToClippings < ActiveRecord::Migration[8.1]
  # Marks a clipping that stays in the queue (newsletter_id NULL) but is held
  # out of the next issue. The deferral is lifted once that issue is composed,
  # so the clipping returns for the following one; a present `deferred_at`
  # means the clipping is currently deferred.
  def change
    add_column :clippings, :deferred_at, :datetime
    add_index :clippings, :deferred_at
  end
end
