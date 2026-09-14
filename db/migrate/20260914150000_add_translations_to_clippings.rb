class AddTranslationsToClippings < ActiveRecord::Migration[8.1]
  # A clipping keeps the title and summary it was clipped with, in the article's
  # own language, plus the translation into the other language. Both are filled
  # when the summary job runs and detects the language; until then the *_for
  # readers fall back to the original.
  def change
    add_column :clippings, :language, :string
    add_column :clippings, :title_translated, :string
    add_column :clippings, :summary_translated, :text
  end
end
