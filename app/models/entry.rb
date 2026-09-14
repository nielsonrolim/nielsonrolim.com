class Entry < ApplicationRecord
  belongs_to :feed
  has_many :clippings, dependent: :destroy

  validates :title, :url, :guid, presence: true
  validates :guid, uniqueness: { scope: :feed_id }

  scope :recent, -> { order(published_at: :desc, id: :desc) }
  scope :since, ->(time) { where("published_at >= ?", time) }

  # An entry is considered clipped while it still has a clipping waiting to be
  # sent out in the next newsletter issue.
  #
  # Uses the preloaded association when the caller already loaded it (so a list
  # does not turn into N+1) and queries otherwise, so the answer is never stale.
  def clipped?
    if association(:clippings).loaded?
      clippings.any? { |clipping| clipping.newsletter_id.nil? }
    else
      clippings.unsent.exists?
    end
  end
end
