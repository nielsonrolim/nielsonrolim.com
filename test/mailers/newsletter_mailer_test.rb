require "test_helper"

class NewsletterMailerTest < ActionMailer::TestCase
  setup do
    @newsletter = newsletters(:last_week)
    @subscriber = subscribers(:first)
    @email = NewsletterMailer.issue(newsletter: @newsletter, subscriber: @subscriber)
  end

  test "goes to the subscriber with the issue subject" do
    assert_equal [ @subscriber.email ], @email.to
    assert_equal @newsletter.subject, @email.subject
  end

  test "comes from the configured sender" do
    assert_equal [ "newsletter@nielsonrolim.com" ], @email.from
  end

  test "carries both an HTML and a plain-text part" do
    assert_equal 2, @email.parts.size

    types = @email.parts.map { |part| part.content_type.to_s.split(";").first }
    assert_includes types, "text/html"
    assert_includes types, "text/plain"
  end

  test "embeds the archived issue body in the HTML part" do
    assert_includes @email.html_part.body.to_s, "Archived issue body"
  end

  test "embeds the archived text body in the plain-text part" do
    assert_includes @email.text_part.body.to_s, "Archived issue body"
  end

  test "appends this recipient's unsubscribe link to both parts" do
    expected = unsubscribe_url_for(@subscriber)

    assert_includes @email.html_part.body.to_s, expected
    assert_includes @email.text_part.body.to_s, expected
    assert_includes @email.html_part.body.to_s, "cancelar inscrição"
  end

  test "names the recipient in the transport footer" do
    assert_includes @email.text_part.body.to_s, "clipping-fan@example.org"
  end

  test "advertises one-click unsubscribe for bulk-mail filters" do
    assert_equal "<#{unsubscribe_url_for(@subscriber)}>", @email["List-Unsubscribe"].to_s
    assert_equal "List-Unsubscribe=One-Click", @email["List-Unsubscribe-Post"].to_s
    assert_equal "auto-generated", @email["Auto-Submitted"].to_s
  end

  test "different subscribers get different unsubscribe links" do
    other = NewsletterMailer.issue(newsletter: @newsletter, subscriber: subscribers(:second))

    assert_not_equal unsubscribe_url_for(@subscriber), unsubscribe_url_for(subscribers(:second))
    assert_not_equal @email["List-Unsubscribe"].to_s, other["List-Unsubscribe"].to_s
  end

  test "sends the body in the subscriber's language" do
    add_english_body

    email = NewsletterMailer.issue(newsletter: @newsletter, subscriber: subscribers(:second))

    assert_equal "Tech clipping — 2026-09-07", email.subject
    assert_includes email.html_part.body.to_s, "Archived issue body (EN)"
  end

  test "writes the transport footer in the subscriber's language too" do
    add_english_body

    email = NewsletterMailer.issue(newsletter: @newsletter, subscriber: subscribers(:second))

    assert_includes email.html_part.body.to_s, "unsubscribe"
    assert_not_includes email.html_part.body.to_s, "cancelar inscrição"
  end

  test "falls back to the default language when the issue lacks the subscriber's" do
    # Only the pt-BR body exists.
    email = NewsletterMailer.issue(newsletter: @newsletter, subscriber: subscribers(:second))

    assert_equal "Clipping de tecnologia — 2026-09-07", email.subject
    assert_includes email.html_part.body.to_s, "Archived issue body"
  end

  test "uses the body it is handed, instead of looking one up" do
    add_english_body
    body = @newsletter.body_for("en-US")

    # The subscriber reads pt-BR, but the job handed over the English body.
    email = NewsletterMailer.issue(newsletter: @newsletter, subscriber: subscribers(:first), body: body)

    assert_equal "Tech clipping — 2026-09-07", email.subject
    assert_includes email.html_part.body.to_s, "Archived issue body (EN)"
  end

  private

  def add_english_body
    @newsletter.bodies.create!(
      locale: "en-US",
      subject: "Tech clipping — 2026-09-07",
      body: "<table><tr><td>Archived issue body (EN)</td></tr></table>",
      body_text: "Archived issue body (EN)"
    )
    @newsletter.bodies.reload
  end

  # Built by hand from the mailer's default_url_options so the expectation does
  # not depend on the same helper the mailer uses.
  def unsubscribe_url_for(subscriber)
    options = ActionMailer::Base.default_url_options
    "http://#{options.fetch(:host)}/newsletter/unsubscribe?token=#{subscriber.unsubscribe_token}"
  end
end
