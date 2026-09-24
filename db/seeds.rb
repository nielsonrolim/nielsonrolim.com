# Idempotent seed: creates the starting set of feeds without hitting the network.
# The first poll is left to RefreshFeedsJob (run `bin/jobs start`, or trigger it
# from the reader UI) so `db:seed` stays fast and works offline.
#
# Each feed lists every category it belongs to: topical ones (Frontend, Ruby,
# Linux, ...) plus the cross-cutting kind (pt-BR for a Brazilian source,
# Agregadores for an aggregator, Podcasts for a podcast). A feed only gets its
# categories when it is first created, so seeding an existing database stays a
# no-op and never overwrites hand-edited categories.
#
#   bin/rails db:seed

FEEDS = [
  # Agregadores (also Engenharia de Software)
  [ "Hacker News", "https://news.ycombinator.com/rss", [ "Engenharia de Software", "Agregadores" ] ],
  [ "Lobsters", "https://lobste.rs/rss", [ "Engenharia de Software", "Agregadores" ] ],
  [ "dev.to", "https://dev.to/feed", [ "Engenharia de Software", "Agregadores" ] ],
  [ "TabNews", "https://www.tabnews.com.br/recentes/rss", [ "Engenharia de Software", "pt-BR", "Agregadores" ] ],

  # Engenharia de Software
  [ "Martin Fowler", "https://martinfowler.com/feed.atom", [ "Engenharia de Software" ] ],
  [ "Coding Horror", "https://blog.codinghorror.com/rss/", [ "Engenharia de Software" ] ],
  [ "Julia Evans", "https://jvns.ca/atom.xml", [ "Engenharia de Software", "Linux" ] ],
  [ "overreacted (Dan Abramov)", "https://overreacted.io/rss.xml", [ "Engenharia de Software", "Frontend" ] ],
  [ "Kent C. Dodds", "https://kentcdodds.com/blog/rss.xml", [ "Engenharia de Software", "Frontend" ] ],
  [ "Pragmatic Engineer", "https://blog.pragmaticengineer.com/rss/", [ "Engenharia de Software" ] ],
  [ "Full Cycle", "https://fullcycle.com.br/feed/", [ "Engenharia de Software", "pt-BR" ] ],
  [ "iMasters", "https://imasters.com.br/feed/", [ "Engenharia de Software", "pt-BR" ] ],

  # Frontend
  [ "CSS-Tricks", "https://css-tricks.com/feed/", [ "Frontend" ] ],
  [ "Smashing Magazine", "https://www.smashingmagazine.com/feed/", [ "Frontend" ] ],
  [ "A List Apart", "https://alistapart.com/main/feed/", [ "Frontend" ] ],
  [ "Josh W. Comeau", "https://www.joshwcomeau.com/rss.xml", [ "Frontend" ] ],
  [ "BrazilJS", "https://www.braziljs.org/feed/", [ "Frontend", "pt-BR" ] ],

  # Ruby
  [ "Ruby on Rails", "https://rubyonrails.org/feed.xml", [ "Ruby" ] ],
  [ "Ruby Weekly", "https://rubyweekly.com/rss/", [ "Ruby" ] ],

  # pt-BR
  [ "Tecnoblog", "https://tecnoblog.net/feed/", [ "pt-BR" ] ],
  [ "Canaltech", "https://canaltech.com.br/rss/", [ "pt-BR" ] ],
  [ "Diolinux", "https://diolinux.com.br/rss", [ "pt-BR", "Linux" ] ],
  [ "Alura — Artigos", "https://www.alura.com.br/artigos/rss", [ "Engenharia de Software", "pt-BR" ] ],
  [ "Mercado de TI", "https://mercadodeti.com.br/feed", [ "pt-BR" ] ],
  [ "Manual do Usuário", "https://manualdousuario.net/feed/", [ "pt-BR" ] ],
  [ "Meio Bit", "https://meiobit.com/feed/", [ "pt-BR" ] ],
  [ "Olhar Digital", "https://olhardigital.com.br/feed/", [ "pt-BR" ] ],
  [ "SempreUpdate", "https://sempreupdate.com.br/feed/", [ "pt-BR" ] ],
  [ "Linux Kamarada", "https://kamarada.github.io/pt/feed.xml", [ "pt-BR", "Linux" ] ],

  # Podcasts
  [ "Hipsters Ponto Tech", "https://hipsters.tech/feed/podcast/", [ "Engenharia de Software", "pt-BR", "Podcasts" ] ],

  # Segurança e Infra
  [ "Krebs on Security", "https://krebsonsecurity.com/feed/", [ "Segurança e Infra" ] ],
  [ "Cloudflare Blog", "https://blog.cloudflare.com/rss/", [ "Segurança e Infra" ] ]
].freeze

created = 0

FEEDS.each do |title, url, categories|
  feed = Feed.find_or_initialize_by(url: url)
  next if feed.persisted?

  feed.title = title
  feed.save!

  categories.each do |category_name|
    category = Category.find_or_create_by_name(category_name)
    feed.categories << category if category
  end

  created += 1
end

puts "Seeded #{created} new feed(s); #{Feed.count} total."
