# Pages that carry a capability in the URL (a subscriber's unsubscribe token, a
# password-reset token) should never leak it through the Referer header. This
# tightens those pages from Rails' default `strict-origin-when-cross-origin` to
# `no-referrer`, so even a same-origin asset request carries no Referer.
module NoReferrer
  extend ActiveSupport::Concern

  included do
    before_action :set_no_referrer_policy
  end

  private

  def set_no_referrer_policy
    response.set_header("Referrer-Policy", "no-referrer")
  end
end
