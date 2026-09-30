# frozen_string_literal: true

# Adds a batch of "Engenharia de Software" sources picked to balance volume,
# depth and pt-BR coverage: two high-frequency individual blogs (Simon Willison,
# antirez), two long-form practitioners (Charity Majors, Will Larson), one news
# aggregator (InfoQ), one company engineering blog (Netflix) and two Brazilian
# engineering blogs (Building Nubank, Codeminer42). Caelum is deliberately
# absent: blog.caelum.com.br now serves the Alura feed, so it would duplicate
# "Alura — Artigos".
#
# Same contract as the other files in db/data — a point-in-time snapshot that
# matches feeds by URL, so re-running is a no-op and an existing feed keeps its
# title and categories. All URLs were checked to return a valid RSS/Atom
# document when this was written.
class ImportEngineeringFeeds < ActiveRecord::Migration[8.1]
  FEEDS = [
    [ "Simon Willison's Weblog",       "https://simonwillison.net/atom/everything/",
      [ "Engenharia de Software" ] ],
    [ "antirez",                       "http://antirez.com/rss",
      [ "Engenharia de Software" ] ],
    [ "Charity Majors",                "https://charity.wtf/feed/",
      [ "Engenharia de Software" ] ],
    [ "Irrational Exuberance (Will Larson)", "https://lethain.com/feeds/",
      [ "Engenharia de Software" ] ],
    [ "InfoQ",                         "https://feed.infoq.com/",
      [ "Engenharia de Software", "Agregadores" ] ],
    [ "Netflix Tech Blog",             "https://netflixtechblog.com/feed",
      [ "Engenharia de Software" ] ],
    [ "Building Nubank",               "https://building.nubank.com.br/feed/",
      [ "Engenharia de Software", "pt-BR" ] ],
    [ "Codeminer42",                   "https://blog.codeminer42.com/feed/",
      [ "Engenharia de Software", "pt-BR" ] ]
  ].freeze

  def up
    FEEDS.each do |title, url, category_names|
      feed = Feed.find_or_create_by!(url: url) { |new_feed| new_feed.title = title }

      category_names.each do |category_name|
        category = Category.find_or_create_by_name(category_name)
        next if category.nil? || feed.categories.any? { |own| own.id == category.id }

        feed.categories << category
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
