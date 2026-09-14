require "test_helper"

class Admin::SubscribersControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup { set_reader_credentials! }
  teardown { restore_reader_credentials! }

  test "requires credentials" do
    get admin_subscribers_path

    assert_response :unauthorized
  end

  test "fails closed when the area is not configured" do
    without_reader_credentials do
      get admin_subscribers_path, headers: reader_headers

      assert_response :forbidden
    end
  end

  test "lists the subscribers with their language and join date" do
    get admin_subscribers_path, headers: reader_headers

    assert_response :success
    assert_select "body", /clipping-fan@example\.org/
    assert_select "body", /clipping-reader@example\.org/

    # Each row carries its language as a select with the current one chosen.
    assert_select "form[action=?] option[selected][value=?]",
                  admin_subscriber_path(subscribers(:first)), "pt-BR"
    assert_select "form[action=?] option[selected][value=?]",
                  admin_subscriber_path(subscribers(:second)), "en-US"
  end

  test "updating a subscriber's language" do
    subscriber = subscribers(:first)

    patch admin_subscriber_path(subscriber),
          params: { subscriber: { language: "en-US" } },
          headers: reader_headers

    assert_equal "en-US", subscriber.reload.language
    assert_redirected_to admin_subscribers_path
  end

  test "a language the site does not speak is refused" do
    subscriber = subscribers(:first)

    patch admin_subscriber_path(subscriber),
          params: { subscriber: { language: "de-DE" } },
          headers: reader_headers

    assert_equal "pt-BR", subscriber.reload.language
    assert_response :redirect
    get admin_subscribers_path, headers: reader_headers
    assert_select ".flash--alert"
  end

  test "shows the copyable unsubscribe link for a subscriber" do
    subscriber = subscribers(:first)

    get admin_subscribers_path, headers: reader_headers

    assert_response :success
    assert_select "input[readonly][value*=?]", subscriber.unsubscribe_token
    assert_select "input[readonly][value*=?]", "/newsletter/unsubscribe"
  end

  test "searches by email fragment" do
    get admin_subscribers_path, params: { q: "reader" }, headers: reader_headers

    assert_response :success
    assert_select "body", /clipping-reader@example\.org/
    assert_select "body", text: /clipping-fan@example\.org/, count: 0
  end

  test "says so when the search matches nobody" do
    get admin_subscribers_path, params: { q: "nobody" }, headers: reader_headers

    assert_response :success
    assert_select "body", /Nenhum inscrito para/
  end

  test "paginates thirty per page" do
    31.times { |index| Subscriber.create!(email: "bulk#{index}@example.com") }
    total = Subscriber.count

    get admin_subscribers_path, headers: reader_headers

    assert_response :success
    assert_select "ol li", count: 30
    assert_select "body", /página 1 de 2/
    assert_select "body", /#{total} inscritos/

    get admin_subscribers_path, params: { page: 2 }, headers: reader_headers

    assert_response :success
    assert_select "ol li", count: total - 30
  end

  test "adding a subscriber records the chosen language" do
    assert_difference -> { Subscriber.count }, 1 do
      post admin_subscribers_path,
           params: { subscriber: { email: "added@example.com", language: "en-US" } },
           headers: reader_headers
    end

    assert_equal "en-US", Subscriber.find_by(email: "added@example.com").language
    assert_redirected_to admin_subscribers_path
  end

  test "adding a duplicate email is reported" do
    assert_no_difference -> { Subscriber.count } do
      post admin_subscribers_path,
           params: { subscriber: { email: subscribers(:first).email, language: "pt-BR" } },
           headers: reader_headers
    end

    assert_response :redirect
    get admin_subscribers_path, headers: reader_headers
    assert_select ".flash--alert"
  end

  test "adding a malformed email is reported" do
    assert_no_difference -> { Subscriber.count } do
      post admin_subscribers_path,
           params: { subscriber: { email: "not-an-email", language: "pt-BR" } },
           headers: reader_headers
    end

    assert_response :redirect
    get admin_subscribers_path, headers: reader_headers
    assert_select ".flash--alert"
  end

  test "removing a subscriber deletes the row" do
    subscriber = subscribers(:first)

    assert_difference -> { Subscriber.count }, -1 do
      delete admin_subscriber_path(subscriber), headers: reader_headers
    end

    assert_nil Subscriber.find_by(id: subscriber.id)
    assert_redirected_to admin_subscribers_path
  end

  test "bulk removal deletes exactly the selected subscribers" do
    keep = subscribers(:second)
    remove_ids = [ subscribers(:first).id, Subscriber.create!(email: "extra@example.com").id ]

    assert_difference -> { Subscriber.count }, -2 do
      delete bulk_destroy_admin_subscribers_path,
             params: { subscriber_ids: remove_ids.map(&:to_s) },
             headers: reader_headers
    end

    assert_not_nil Subscriber.find_by(id: keep.id)
    assert_redirected_to admin_subscribers_path
  end

  test "bulk removal with nothing selected is harmless" do
    assert_no_difference -> { Subscriber.count } do
      delete bulk_destroy_admin_subscribers_path, params: { subscriber_ids: [ "" ] }, headers: reader_headers
    end

    assert_redirected_to admin_subscribers_path
  end

  test "exports the subscribers as CSV" do
    get export_admin_subscribers_path, headers: reader_headers

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_match(/attachment; filename="subscribers-\d{4}-\d{2}-\d{2}\.csv"/, response.headers["Content-Disposition"])

    body = response.body
    assert_includes body, "email,language,created_at"
    assert_includes body, "clipping-reader@example.org,en-US"
  end

  test "the export follows the current search" do
    get export_admin_subscribers_path, params: { q: "reader" }, headers: reader_headers

    assert_includes response.body, "clipping-reader@example.org"
    assert_not_includes response.body, "clipping-fan@example.org"
  end

  test "resending an issue queues the mail for that subscriber" do
    subscriber = subscribers(:second)

    assert_enqueued_emails 1 do
      post resend_admin_subscriber_path(subscriber),
           params: { newsletter_id: newsletters(:last_week).id },
           headers: reader_headers
    end

    assert_redirected_to admin_subscribers_path
  end

  test "offers a resend picker with the recent sent issues" do
    get admin_subscribers_path, headers: reader_headers

    assert_response :success
    assert_select "select[name=?]", "newsletter_id"
    assert_select "option[value=?]", newsletters(:last_week).id.to_s
  end

  test "offers no resend picker when nothing has been sent" do
    Newsletter.destroy_all

    get admin_subscribers_path, headers: reader_headers

    assert_response :success
    assert_select "select[name=?]", "newsletter_id", count: 0
  end

  test "the admin navigation links to the subscribers page" do
    get admin_root_path, headers: reader_headers

    assert_select "nav a[href=?]", admin_subscribers_path
    assert_select "nav", /\[inscritos\]/
  end
end
