class Newsletter < ApplicationRecord
  has_many :clippings, dependent: :nullify

  enum :status, {
    draft: "draft",
    sending: "sending",
    sent: "sent",
    failed: "failed"
  }

  validates :subject, presence: true
  validates :body, presence: true

  scope :newest_first, -> { order(created_at: :desc) }
end
