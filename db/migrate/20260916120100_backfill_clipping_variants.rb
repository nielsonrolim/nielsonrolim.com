class BackfillClippingVariants < ActiveRecord::Migration[8.1]
  # Moves each clipping's existing content into variants: the article's own
  # language becomes the source variant, and the translation (when present)
  # becomes the other one, both pointing at the URL the clipping already had.
  #
  # Runs before the localized columns are dropped, so it has to be a schema
  # migration and not a db/data one: data migrations run after db:prepare, once
  # the columns are already gone.
  def up
    execute <<~SQL
      INSERT INTO clipping_variants
        (clipping_id, locale, url, title, summary, origin, created_at, updated_at)
      SELECT id, language, url, title, summary, 'generated', created_at, updated_at
      FROM clippings
    SQL

    execute <<~SQL
      INSERT INTO clipping_variants
        (clipping_id, locale, url, title, summary, origin, created_at, updated_at)
      SELECT id,
             CASE WHEN language = 'pt-BR' THEN 'en-US' ELSE 'pt-BR' END,
             url,
             COALESCE(title_translated, title),
             summary_translated,
             'generated',
             created_at,
             updated_at
      FROM clippings
      WHERE language IS NOT NULL
        AND (title_translated IS NOT NULL OR summary_translated IS NOT NULL)
    SQL
  end

  def down
    execute "DELETE FROM clipping_variants"
  end
end
