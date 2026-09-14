class Subscriber < ApplicationRecord
  attr_accessor :nickname

  validates :email, presence: true,
                     format: { with: URI::MailTo::EMAIL_REGEXP },
                     uniqueness: { case_sensitive: false }
  validates :unsubscribe_token, uniqueness: true, allow_nil: true

  before_validation :ensure_unsubscribe_token, on: :create

  # Looks a subscriber up by the token embedded in an email's unsubscribe link.
  def self.find_by_unsubscribe_token(token)
    return nil if token.blank?

    find_by(unsubscribe_token: token)
  end

  private

  def ensure_unsubscribe_token
    self.unsubscribe_token ||= SecureRandom.urlsafe_base64(24)
  end
end
