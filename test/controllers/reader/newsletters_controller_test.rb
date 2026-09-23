require "test_helper"

class Reader::NewslettersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as_admin
  end

  teardown do
    sign_out
  end

  test "lists past issues with their stats" do
    get reader_newsletters_path

    assert_response :success
    assert_select "body", /Clipping de tecnologia — 2026-09-07/
    assert_select "body", /enviada/
    assert_select "body", /na fila: 2/
    assert_select "body", /assinantes: 2/
    assert_select "body", /segundas, 09:00/
  end

  test "triggering a send queues the weekly job" do
    assert_enqueued_with(job: SendNewsletterJob) do
      post reader_newsletters_path
    end

    assert_redirected_to reader_newsletters_path
  end

  test "shows an archived issue exactly as it was stored" do
    newsletter = newsletters(:last_week)

    get reader_newsletter_path(newsletter)

    assert_response :success
    assert_select "h1", newsletter.subject
    # The stored HTML is handed to an iframe so its inline styles stay isolated.
    assert_select "iframe[srcdoc*=?]", "Archived issue body", 1
  end

  test "a missing issue is a 404" do
    get reader_newsletter_path(-1)

    assert_response :not_found
  end

  test "offers a language tab per body when the issue went out in more than one" do
    newsletter = newsletters(:last_week)
    add_english_body(newsletter)

    get reader_newsletter_path(newsletter)

    assert_response :success
    assert_select "a[href*=?]", "issue_locale=pt-BR"
    assert_select "a[href*=?]", "issue_locale=en-US"
  end

  test "lists the languages each issue went out in" do
    add_english_body(newsletters(:last_week))

    get reader_newsletters_path

    assert_response :success
    assert_select "body", /idiomas: (en-US · pt-BR|pt-BR · en-US)/
  end

  test "shows the body for the requested language" do
    newsletter = newsletters(:last_week)
    add_english_body(newsletter)

    get reader_newsletter_path(newsletter, issue_locale: "en-US")

    assert_response :success
    assert_select "iframe[srcdoc*=?]", "English body"
    assert_select "h1", "Tech clipping"
  end

  test "hides the language tabs for a single-language issue" do
    get reader_newsletter_path(newsletters(:last_week))

    assert_response :success
    assert_select "a[href*=?]", "issue_locale=", count: 0
  end

  private

  def add_english_body(newsletter)
    newsletter.bodies.create!(
      locale: "en-US",
      subject: "Tech clipping",
      body: "<table><tr><td>English body</td></tr></table>",
      body_text: "English body"
    )
    newsletter.bodies.reload
  end
end
