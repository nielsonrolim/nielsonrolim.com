# frozen_string_literal: true

# Brings the feed set authored in development into whatever database this runs
# against — production included — via `bin/rails data:migrate`.
#
# The list is a point-in-time snapshot on purpose: a data migration has to keep
# meaning the same thing forever, so it deliberately does not read db/seeds.rb
# (which keeps evolving). Feeds are matched by URL, so re-running is a no-op and
# a feed that already exists in the target database is left untouched — including
# its title and category, which the app may have refreshed from the feed itself.
class ImportDevelopmentFeeds < ActiveRecord::Migration[8.1]
  FEEDS = [
    [ "DEV Community", "https://dev.to/feed", "Agregadores" ],
    [ "Hacker News", "https://news.ycombinator.com/rss", "Agregadores" ],
    [ "Lobsters", "https://lobste.rs/rss", "Agregadores" ],
    [ "TabNews", "https://www.tabnews.com.br/recentes/rss", "Agregadores" ],
    [ "Coding Horror", "https://blog.codinghorror.com/rss/", "Engenharia" ],
    [ "Julia Evans", "https://jvns.ca/atom.xml", "Engenharia" ],
    [ "Kent C. Dodds Blog", "https://kentcdodds.com/blog/rss.xml", "Engenharia" ],
    [ "Martin Fowler", "https://martinfowler.com/feed.atom", "Engenharia" ],
    [ "The Pragmatic Engineer", "https://blog.pragmaticengineer.com/rss/", "Engenharia" ],
    [ "overreacted — A blog by Dan Abramov", "https://overreacted.io/rss.xml", "Engenharia" ],
    [ "A List Apart: The Full Feed", "https://alistapart.com/main/feed/", "Frontend" ],
    [ "Articles on Smashing Magazine — For Web Designers And Developers", "https://www.smashingmagazine.com/feed/", "Frontend" ],
    [ "BrazilJS", "https://www.braziljs.org/feed/", "Frontend" ],
    [ "CSS-Tricks", "https://css-tricks.com/feed/", "Frontend" ],
    [ "Josh Comeau's blog", "https://www.joshwcomeau.com/rss.xml", "Frontend" ],
    [ "Ruby Weekly", "https://rubyweekly.com/rss/", "Ruby" ],
    [ "Ruby on Rails: Compress the complexity of modern web apps", "https://rubyonrails.org/feed.xml", "Ruby" ],
    [ "Cloudflare Blog", "https://blog.cloudflare.com/rss/", "Segurança e Infra" ],
    [ "Krebs on Security", "https://krebsonsecurity.com/feed/", "Segurança e Infra" ],
    [ "Canaltech", "https://canaltech.com.br/rss/", "Tecnologia (pt-BR)" ],
    [ "Diolinux", "https://diolinux.com.br/rss", "Tecnologia (pt-BR)" ],
    [ "Mercado de Ti", "https://mercadodeti.com.br/feed", "Tecnologia (pt-BR)" ],
    [ "Tecnoblog", "https://tecnoblog.net/feed/", "Tecnologia (pt-BR)" ],
    [ "Veja nossos artigos", "https://www.alura.com.br/artigos/rss", "Tecnologia (pt-BR)" ]
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
