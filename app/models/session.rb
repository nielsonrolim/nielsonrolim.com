class Session < ApplicationRecord
  # A session cookie is permanent, so the row carries its own expiry: a token
  # that leaked stays valid for at most this long, even without an explicit
  # logout or password reset.
  DURATION = 30.days

  belongs_to :user

  before_create { self.expires_at ||= DURATION.from_now }

  def expired?
    expires_at.present? && expires_at.past?
  end
end
