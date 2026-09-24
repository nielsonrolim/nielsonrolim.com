# frozen_string_literal: true

# Reshapes the category taxonomy: "Engenharia" becomes "Engenharia de Software"
# and "Tecnologia (pt-BR)" becomes "pt-BR", then fills in the cross-cutting
# memberships that make a source show up under both its topic and its kind — a
# Brazilian source also carries "pt-BR", an aggregator also carries
# "Agregadores", the podcast also carries "Podcasts".
#
# Like the other files in db/data this is a point-in-time snapshot. Renames keep
# the existing membership, so a feed that already had the category is left alone;
# only the recipients listed in ADD gain a new one, and a URL that is not in the
# database is skipped rather than recreated. Re-running is therefore a no-op.
class ReorganizeFeedCategories < ActiveRecord::Migration[8.1]
  RENAME = {
    "Engenharia"         => "Engenharia de Software",
    "Tecnologia (pt-BR)" => "pt-BR"
  }.freeze

  # Memberships the renames do not already carry, keyed by category and matched
  # to feeds by URL.
  ADD = {
    "Frontend" => %w[
      https://overreacted.io/rss.xml
      https://kentcdodds.com/blog/rss.xml
    ],
    "Engenharia de Software" => %w[
      https://news.ycombinator.com/rss
      https://lobste.rs/rss
      https://dev.to/feed
      https://www.tabnews.com.br/recentes/rss
      https://hipsters.tech/feed/podcast/
      https://www.alura.com.br/artigos/rss
    ],
    "pt-BR" => %w[
      https://www.tabnews.com.br/recentes/rss
      https://fullcycle.com.br/feed/
      https://imasters.com.br/feed/
      https://hipsters.tech/feed/podcast/
      https://www.braziljs.org/feed/
    ],
    "Linux" => %w[
      https://diolinux.com.br/rss
      https://kamarada.github.io/pt/feed.xml
      https://jvns.ca/atom.xml
    ]
  }.freeze

  def up
    RENAME.each do |old_name, new_name|
      old = find_category(old_name)
      next if old.nil?

      target = find_category(new_name)
      if target
        move_memberships(old, target)
        old.destroy
      else
        old.update!(name: new_name)
      end
    end

    ADD.each do |category_name, urls|
      category = Category.find_or_create_by_name(category_name)
      next if category.nil?

      urls.each do |url|
        feed = Feed.find_by(url: url)
        next if feed.nil? || feed.categories.any? { |own| own.id == category.id }

        feed.categories << category
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def find_category(name)
    Category.find_by("lower(name) = ?", name.downcase)
  end

  # Used only if both the old and the new name exist — keeps the feeds that
  # pointed at the old record before dropping it.
  def move_memberships(from, to)
    from.feeds.find_each do |feed|
      feed.categories << to unless feed.categories.any? { |own| own.id == to.id }
    end
  end
end
