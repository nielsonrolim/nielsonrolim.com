class NewsletterBody < ApplicationRecord
  belongs_to :newsletter

  validates :locale, presence: true, uniqueness: { scope: :newsletter_id }
  validates :subject, presence: true
  validates :body, presence: true
end
