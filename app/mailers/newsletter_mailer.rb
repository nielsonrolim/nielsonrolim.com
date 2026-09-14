class NewsletterMailer < ApplicationMailer
  # Sends one archived issue to one subscriber.
  #
  # The issue body is rendered once and stored on the Newsletter; only the
  # transport-level footer (which carries this recipient's unsubscribe token)
  # varies per recipient.
  def issue(newsletter:, subscriber:)
    @newsletter = newsletter
    @subscriber = subscriber
    @unsubscribe_url = unsubscribe_url(token: subscriber.unsubscribe_token)

    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    headers["Auto-Submitted"] = "auto-generated"

    mail(to: subscriber.email, subject: newsletter.subject)
  end
end
