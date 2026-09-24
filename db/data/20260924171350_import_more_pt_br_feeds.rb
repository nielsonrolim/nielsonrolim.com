# frozen_string_literal: true

# Adds a second batch of pt-BR sources to the feed set: tech news, a few
# engineering blogs and a podcast category. Same contract as
# 20260914122758_import_development_feeds.rb — a point-in-time snapshot that
# matches feeds by URL, so re-running is a no-op and an existing feed keeps its
# title and categories. "Mercado de TI" is repeated on purpose: it recreates the
# feed if it was deleted and re-attaches the category if it was detached.
class ImportMorePtBrFeeds < ActiveRecord::Migration[8.1]
  FEEDS = [
    [ "Manual do Usuário",   "https://manualdousuario.net/feed/",      "Tecnologia (pt-BR)" ],
    [ "Meio Bit",            "https://meiobit.com/feed/",              "Tecnologia (pt-BR)" ],
    [ "Olhar Digital",       "https://olhardigital.com.br/feed/",      "Tecnologia (pt-BR)" ],
    [ "SempreUpdate",        "https://sempreupdate.com.br/feed/",      "Tecnologia (pt-BR)" ],
    [ "Linux Kamarada",      "https://kamarada.github.io/pt/feed.xml", "Tecnologia (pt-BR)" ],
    [ "Mercado de TI",       "https://mercadodeti.com.br/feed",        "Tecnologia (pt-BR)" ],
    [ "Full Cycle",          "https://fullcycle.com.br/feed/",         "Engenharia" ],
    [ "iMasters",            "https://imasters.com.br/feed/",          "Engenharia" ],
    [ "Hipsters Ponto Tech", "https://hipsters.tech/feed/podcast/",    "Podcasts" ]
  ].freeze

  def up
    FEEDS.each do |title, url, category_name|
      feed = Feed.find_or_create_by!(url: url) { |new_feed| new_feed.title = title }

      category = Category.find_or_create_by_name(category_name)
      next if category.nil? || feed.categories.any? { |own| own.id == category.id }

      feed.categories << category
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
