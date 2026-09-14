require "csv"

class Subscriber < ApplicationRecord
  # The site's locales are the newsletter languages; storing the locale string
  # itself lets the mailer do I18n.with_locale(subscriber.language) directly.
  LANGUAGES = I18n.available_locales.map(&:to_s).freeze

  attr_accessor :nickname

  validates :email, presence: true,
                     format: { with: URI::MailTo::EMAIL_REGEXP },
                     uniqueness: { case_sensitive: false }
  validates :language, inclusion: { in: LANGUAGES }
  validates :unsubscribe_token, uniqueness: true, allow_nil: true

  before_validation :ensure_unsubscribe_token, on: :create

  scope :newest_first, -> { order(created_at: :desc) }

  # Looks a subscriber up by the token embedded in an email's unsubscribe link.
  def self.find_by_unsubscribe_token(token)
    return nil if token.blank?

    find_by(unsubscribe_token: token)
  end

  # Emails matching `query`, case-insensitively. The search box on the admin
  # page is the only caller.
  def self.search(query)
    term = query.to_s.strip
    return all if term.blank?

    where("email LIKE ?", "%#{sanitize_sql_like(term.downcase)}%")
  end

  # CSV for the admin export. The header stays language-neutral on purpose: it is
  # a file to open in a spreadsheet, not copy in the UI.
  def self.to_csv(subscribers)
    CSV.generate do |csv|
      csv << %w[email language created_at]
      subscribers.each do |subscriber|
        csv << [ subscriber.email, subscriber.language, subscriber.created_at.iso8601 ]
      end
    end
  end

  private

  def ensure_unsubscribe_token
    self.unsubscribe_token ||= SecureRandom.urlsafe_base64(24)
  end
end
