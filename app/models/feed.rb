class Feed < ApplicationRecord
  has_many :entries, dependent: :destroy

  validates :title, presence: true
  validates :url, presence: true,
                  uniqueness: true,
                  format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }

  scope :alphabetical, -> { order(Arel.sql("lower(title)")) }

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
