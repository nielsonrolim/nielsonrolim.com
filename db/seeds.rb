# Idempotent seed: creates the starting set of feeds without hitting the network.
# The first poll is left to RefreshFeedsJob (run `bin/jobs start`, or trigger it
# from the reader UI) so `db:seed` stays fast and works offline.
#
#   bin/rails db:seed

FEEDS = {
  "Agregadores" => [
    [ "Hacker News", "https://news.ycombinator.com/rss" ],
    [ "Lobsters", "https://lobste.rs/rss" ],
    [ "dev.to", "https://dev.to/feed" ],
    [ "TabNews", "https://www.tabnews.com.br/recentes/rss" ]
  ],
  "Engenharia" => [
    [ "Martin Fowler", "https://martinfowler.com/feed.atom" ],
    [ "Coding Horror", "https://blog.codinghorror.com/rss/" ],
    [ "Julia Evans", "https://jvns.ca/atom.xml" ],
    [ "overreacted (Dan Abramov)", "https://overreacted.io/rss.xml" ],
    [ "Kent C. Dodds", "https://kentcdodds.com/blog/rss.xml" ],
    [ "Pragmatic Engineer", "https://blog.pragmaticengineer.com/rss/" ]
  ],
  "Frontend" => [
    [ "CSS-Tricks", "https://css-tricks.com/feed/" ],
    [ "Smashing Magazine", "https://www.smashingmagazine.com/feed/" ],
    [ "A List Apart", "https://alistapart.com/main/feed/" ],
    [ "Josh W. Comeau", "https://www.joshwcomeau.com/rss.xml" ],
    [ "BrazilJS", "https://www.braziljs.org/feed/" ]
  ],
  "Ruby" => [
    [ "Ruby on Rails", "https://rubyonrails.org/feed.xml" ],
    [ "Ruby Weekly", "https://rubyweekly.com/rss/" ]
  ],
  "Tecnologia (pt-BR)" => [
    [ "Tecnoblog", "https://tecnoblog.net/feed/" ],
    [ "Canaltech", "https://canaltech.com.br/rss/" ],
    [ "Diolinux", "https://diolinux.com.br/rss" ],
    [ "Alura — Artigos", "https://www.alura.com.br/artigos/rss" ],
    [ "Mercado de TI", "https://mercadodeti.com.br/feed" ]
  ],
  "Segurança e Infra" => [
    [ "Krebs on Security", "https://krebsonsecurity.com/feed/" ],
    [ "Cloudflare Blog", "https://blog.cloudflare.com/rss/" ]
  ]
}.freeze

created = 0

FEEDS.each do |category_name, feeds|
  category = Category.find_or_create_by_name(category_name)

  feeds.each do |title, url|
    feed = Feed.find_or_initialize_by(url: url)
    next if feed.persisted?

    feed.title = title
    feed.save!
    feed.categories << category if category
    created += 1
  end
end

puts "Seeded #{created} new feed(s); #{Feed.count} total."
