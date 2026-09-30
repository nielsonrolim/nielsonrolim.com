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
  [ "InfoQ", "https://feed.infoq.com/", [ "Engenharia de Software", "Agregadores" ] ],

  # Engenharia de Software
  [ "Simon Willison's Weblog", "https://simonwillison.net/atom/everything/", [ "Engenharia de Software" ] ],
  [ "antirez", "http://antirez.com/rss", [ "Engenharia de Software" ] ],
  [ "Charity Majors", "https://charity.wtf/feed/", [ "Engenharia de Software" ] ],
  [ "Irrational Exuberance (Will Larson)", "https://lethain.com/feeds/", [ "Engenharia de Software" ] ],
  [ "Netflix Tech Blog", "https://netflixtechblog.com/feed", [ "Engenharia de Software" ] ],
  [ "Building Nubank", "https://building.nubank.com.br/feed/", [ "Engenharia de Software", "pt-BR" ] ],
  [ "Codeminer42", "https://blog.codeminer42.com/feed/", [ "Engenharia de Software", "pt-BR" ] ],
  [ "diegoeis.com", "https://diegoeis.com/feed/", [ "Engenharia de Software", "pt-BR" ] ],
  [ "Elton Minetto", "https://eltonminetto.dev/index.xml", [ "Engenharia de Software", "pt-BR" ] ],
  [ "Hillel Wayne", "https://buttondown.com/hillelwayne/rss", [ "Engenharia de Software" ] ],
  [ "Dan McKinley", "https://mcfunley.com/feed.xml", [ "Engenharia de Software" ] ],
  [ "Armin Ronacher", "https://lucumr.pocoo.org/feed.atom", [ "Engenharia de Software" ] ],
  [ "The Old New Thing (Raymond Chen)", "https://devblogs.microsoft.com/oldnewthing/feed", [ "Engenharia de Software" ] ],
  [ "Alex Ewerlöf", "https://blog.alexewerlof.com/feed", [ "Engenharia de Software" ] ],
  [ "Thorsten Ball", "https://registerspill.thorstenball.com/feed", [ "Engenharia de Software" ] ],
  [ "CodeOpinion (Derek Comartin)", "https://codeopinion.com/feed/", [ "Engenharia de Software" ] ],
  [ "Andrew Lock", "https://andrewlock.net/rss.xml", [ "Engenharia de Software" ] ],
  [ "Steve Klabnik", "https://steveklabnik.com/feed.xml", [ "Engenharia de Software" ] ],
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
  [ "Jim Nielsen", "https://blog.jim-nielsen.com/feed.xml", [ "Frontend" ] ],
  [ "Nikita Prokopov (tonsky)", "https://tonsky.me/blog/atom.xml", [ "Frontend" ] ],
  [ "BrazilJS", "https://www.braziljs.org/feed/", [ "Frontend", "pt-BR" ] ],
  [ "Felipe Fialho", "https://www.felipefialho.com/feed.xml", [ "Frontend", "pt-BR" ] ],

  # Ruby
  [ "Ruby on Rails", "https://rubyonrails.org/feed.xml", [ "Ruby" ] ],
  [ "Ruby Weekly", "https://rubyweekly.com/rss/", [ "Ruby" ] ],
  [ "Lucas Caton", "https://lucascaton.com.br/feed.xml", [ "Ruby", "pt-BR" ] ],

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
  [ "Cloudflare Blog", "https://blog.cloudflare.com/rss/", [ "Segurança e Infra" ] ],
  [ "Bruce Schneier", "https://www.schneier.com/blog/atom.xml", [ "Segurança e Infra" ] ],

  # Linux
  [ "Jeff Geerling", "https://www.jeffgeerling.com/blog.xml", [ "Linux" ] ]
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
