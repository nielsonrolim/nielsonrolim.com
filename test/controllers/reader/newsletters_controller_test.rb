require "test_helper"

class Reader::NewslettersControllerTest < ActionDispatch::IntegrationTest
  setup do
    set_reader_credentials!
  end

  teardown do
    restore_reader_credentials!
  end

  test "lists past issues with their stats" do
    get reader_newsletters_path, headers: reader_headers

    assert_response :success
    assert_select "body", /Clipping de tecnologia — 2026-09-07/
    assert_select "body", /enviada/
    assert_select "body", /na fila: 2/
    assert_select "body", /assinantes: 2/
    assert_select "body", /segundas, 09:00/
  end

  test "triggering a send queues the weekly job" do
    assert_enqueued_with(job: SendNewsletterJob) do
      post reader_newsletters_path, headers: reader_headers
    end

    assert_redirected_to reader_newsletters_path
  end

  test "shows an archived issue exactly as it was stored" do
    newsletter = newsletters(:last_week)

    get reader_newsletter_path(newsletter), headers: reader_headers

    assert_response :success
    assert_select "h1", newsletter.subject
    # The stored HTML is handed to an iframe so its inline styles stay isolated.
    assert_select "iframe[srcdoc*=?]", "Archived issue body", 1
  end

  test "a missing issue is a 404" do
    get reader_newsletter_path(-1), headers: reader_headers

    assert_response :not_found
  end
end
