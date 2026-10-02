class NewsletterMailer < ApplicationMailer
  # Sends one archived issue to one subscriber, in their language.
  #
  # The bodies are rendered once and stored per locale; the caller (the send job)
  # passes the one matching the recipient, so a batch does not re-query per
  # address. Resending from the admin lets the mailer find it.
  def issue(newsletter:, subscriber:, body: nil)
    @newsletter = newsletter
    @subscriber = subscriber
    @issue_body = body || newsletter.body_for(subscriber.language)
    @unsubscribe_url = unsubscribe_url(token: subscriber.unsubscribe_token)
    @preferences_url = preferences_url(token: subscriber.unsubscribe_token)
    @newsletter_url = newsletter_url(locale: subscriber.language)

    headers["List-Unsubscribe"] = "<#{@unsubscribe_url}>"
    headers["List-Unsubscribe-Post"] = "List-Unsubscribe=One-Click"
    headers["Auto-Submitted"] = "auto-generated"
    # A stable per-issue id keeps Gmail from collapsing every issue into one thread.
    headers["X-Entity-Ref-ID"] = "newsletter-#{newsletter.id}"

    # Wraps the footer strings too, so the transport lines match the body.
    I18n.with_locale(subscriber.language) do
      mail(to: subscriber.email, subject: @issue_body.subject, reply_to: reply_to)
    end
  end

  private

  # Replies go to a monitored inbox, not the send-only From address. Overridable
  # per environment.
  def reply_to
    ENV.fetch("NEWSLETTER_REPLY_TO", "Nielson Rolim <contato@nielsonrolim.com>")
  end
end
