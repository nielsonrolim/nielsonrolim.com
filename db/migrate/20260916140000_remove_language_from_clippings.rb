class RemoveLanguageFromClippings < ActiveRecord::Migration[8.1]
  # The language editions are on clipping_variants now; the clipping no longer
  # needs to remember a single "article language". Which languages a story is
  # published in is the set of variants that carry a URL.
  def change
    remove_column :clippings, :language, :string
  end
end
