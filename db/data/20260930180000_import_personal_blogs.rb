# frozen_string_literal: true

# Adds a batch of personal engineering blogs — the "one author, no editorial
# board" kind that keeps the reader varied beyond company blogs and
# aggregators. Chosen for being actively published (last post checked when this
# was written), split across the topic categories so each one lands where a
# reader would expect it: Frontend, Linux, Segurança e Infra, and four
# Brazilian authors under pt-BR.
#
# Same contract as the other files in db/data — a point-in-time snapshot that
# matches feeds by URL, so re-running is a no-op and an existing feed keeps its
# title and categories.
class ImportPersonalBlogs < ActiveRecord::Migration[8.1]
  FEEDS = [
    [ "Hillel Wayne",                   "https://buttondown.com/hillelwayne/rss",
      [ "Engenharia de Software" ] ],
    [ "Dan McKinley",                   "https://mcfunley.com/feed.xml",
      [ "Engenharia de Software" ] ],
    [ "Armin Ronacher",                 "https://lucumr.pocoo.org/feed.atom",
      [ "Engenharia de Software" ] ],
    [ "The Old New Thing (Raymond Chen)", "https://devblogs.microsoft.com/oldnewthing/feed",
      [ "Engenharia de Software" ] ],
    [ "Alex Ewerlöf",                   "https://blog.alexewerlof.com/feed",
      [ "Engenharia de Software" ] ],
    [ "Thorsten Ball",                  "https://registerspill.thorstenball.com/feed",
      [ "Engenharia de Software" ] ],
    [ "CodeOpinion (Derek Comartin)",   "https://codeopinion.com/feed/",
      [ "Engenharia de Software" ] ],
    [ "Andrew Lock",                    "https://andrewlock.net/rss.xml",
      [ "Engenharia de Software" ] ],
    [ "Steve Klabnik",                  "https://steveklabnik.com/feed.xml",
      [ "Engenharia de Software" ] ],
    [ "Jim Nielsen",                    "https://blog.jim-nielsen.com/feed.xml",
      [ "Frontend" ] ],
    [ "Nikita Prokopov (tonsky)",       "https://tonsky.me/blog/atom.xml",
      [ "Frontend" ] ],
    [ "Jeff Geerling",                  "https://www.jeffgeerling.com/blog.xml",
      [ "Linux" ] ],
    [ "Bruce Schneier",                 "https://www.schneier.com/blog/atom.xml",
      [ "Segurança e Infra" ] ],
    [ "diegoeis.com",                   "https://diegoeis.com/feed/",
      [ "Engenharia de Software", "pt-BR" ] ],
    [ "Elton Minetto",                  "https://eltonminetto.dev/index.xml",
      [ "Engenharia de Software", "pt-BR" ] ],
    [ "Felipe Fialho",                  "https://www.felipefialho.com/feed.xml",
      [ "Frontend", "pt-BR" ] ],
    [ "Lucas Caton",                    "https://lucascaton.com.br/feed.xml",
      [ "Ruby", "pt-BR" ] ]
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
