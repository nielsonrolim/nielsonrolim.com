class FeedCategory < ApplicationRecord
  belongs_to :feed
  belongs_to :category
end
