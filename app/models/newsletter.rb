class Newsletter < ApplicationRecord
  # One rendered version per language: a subscriber receives the body matching
  # their language, falling back to the app's default when the issue does not
  # carry theirs.
  has_many :bodies, -> { order(:locale) }, class_name: "NewsletterBody",
           inverse_of: :newsletter, dependent: :destroy
  has_many :clippings, dependent: :nullify

  enum :status, {
    draft: "draft",
    sending: "sending",
    sent: "sent",
    failed: "failed"
  }

  scope :newest_first, -> { order(created_at: :desc) }

  # The body to send to `locale`, in order of preference: exactly that language,
  # then the default one, then whatever the issue has. `detect` walks the loaded
  # association rather than querying, so a preloaded archive does not go N+1.
  def body_for(locale)
    target = locale.to_s
    bodies.detect { |body| body.locale == target } ||
      bodies.detect { |body| body.locale == self.class.default_locale } ||
      bodies.first
  end

  def locales
    bodies.map(&:locale)
  end

  # The canonical copy, used by the archive list and as the default-language
  # reader. Keeps older call sites working after the columns moved to bodies.
  def subject
    body_for(self.class.default_locale)&.subject
  end

  def body
    body_for(self.class.default_locale)&.body
  end

  def body_text
    body_for(self.class.default_locale)&.body_text
  end

  def self.default_locale
    I18n.default_locale.to_s
  end
end
