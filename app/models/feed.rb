class Feed < ApplicationRecord
  has_many :entries, dependent: :destroy
  has_many :feed_categories, dependent: :destroy
  has_many :categories, through: :feed_categories

  # Form-only field backing the compact "add feed" input. Categories are a real
  # association now, so this is deliberately not a column: the controller reads
  # it and attaches the category itself.
  attr_accessor :category

  validates :title, presence: true
  validates :url, presence: true,
                  uniqueness: true,
                  format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }

  # Sort by what the reader actually sees, which is the custom title when set.
  scope :alphabetical, lambda {
    order(Arel.sql("lower(COALESCE(NULLIF(custom_title, ''), title))"))
  }

  # The name to show: the user's override when there is one, otherwise the title
  # learned from the feed (which keeps being refreshed on every poll).
  def display_title
    custom_title.presence || title
  end

  # Feeds that are due for another poll: never fetched, or fetched before the
  # given cutoff.
  def self.stale_before(cutoff)
    where(last_fetched_at: nil).or(where(Feed.arel_table[:last_fetched_at].lt(cutoff)))
  end

  def fetched?
    last_fetched_at.present?
  end

  def healthy?
    last_error.blank?
  end
end
