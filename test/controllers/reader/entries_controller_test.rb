require "test_helper"

class Reader::EntriesControllerTest < ActionDispatch::IntegrationTest
  setup do
    set_reader_credentials!
  end

  teardown do
    restore_reader_credentials!
  end

  test "lists entries newest first with their feed" do
    get reader_entries_path, headers: reader_headers

    assert_response :success
    assert_select "body", /Solid Queue internals/
    assert_select "body", /Show HN: I built an RSS reader in Rails/
    assert_select "body", /Ruby Weekly/

    body = response.body
    assert_operator body.index("Solid Queue internals"), :<, body.index("Rails 8.1 ships with a new queue UI")
  end

  test "filters by feed" do
    get reader_entries_path, params: { feed_id: feeds(:hacker_news).id }, headers: reader_headers

    assert_response :success
    assert_select "body", /Show HN/
    assert_select "body", text: /Solid Queue internals/, count: 0
  end

  test "filters by publication window" do
    get reader_entries_path, params: { since: 1 }, headers: reader_headers

    assert_response :success
    assert_select "body", /Show HN/                          # 3 hours ago
    assert_select "body", /Solid Queue internals/            # 20 hours ago
    assert_select "body", text: /Rails 8\.1 ships/, count: 0 # 3 days ago
  end

  test "ignores a nonsense window filter" do
    get reader_entries_path, params: { since: "abc" }, headers: reader_headers

    assert_response :success
    assert_select "body", /Rails 8\.1 ships/
  end

  test "paginates at fifty entries per page" do
    feed = feeds(:ruby_blog)
    60.times do |i|
      Entry.create!(feed: feed, guid: "bulk-#{i}", title: "Bulk entry #{i}",
                    url: "https://example.com/bulk/#{i}", published_at: i.minutes.ago)
    end

    get reader_entries_path, headers: reader_headers
    assert_response :success
    assert_select "body", /página 1 de 2/
    assert_select "a", /próxima/

    get reader_entries_path, params: { page: 2 }, headers: reader_headers
    assert_response :success
    assert_select "body", /página 2 de 2/
  end

  test "shows the clipped state for an entry already in the queue" do
    get reader_entries_path, headers: reader_headers

    assert_response :success
    assert_select "body", /na próxima edição/
  end

  test "links to the job dashboard from the reader navigation" do
    get reader_entries_path, headers: reader_headers

    assert_response :success
    assert_select "nav a[href=?]", admin_mission_control_jobs_path
    assert_select "nav", /\[jobs\]/
  end

  test "renders both navigation levels" do
    get reader_entries_path, headers: reader_headers

    assert_response :success
    # Top level: the admin sections.
    assert_select "nav", /\[painel\]/
    assert_select "nav", /\[leitor\]/
    # Second level: the reader's own sections.
    assert_select "nav a[href=?]", reader_feeds_path
    assert_select "nav", /\[entradas\]/
    assert_select "nav", /\[recortes\]/
  end

  test "clipping an entry queues it and asks for a summary" do
    entry = entries(:front_page)

    assert_difference -> { Clipping.count }, 1 do
      assert_enqueued_with(job: GenerateSummaryJob) do
        post clip_reader_entry_path(entry), headers: reader_headers
      end
    end

    clipping = Clipping.find_by(entry: entry, newsletter_id: nil)
    assert_equal entry.title, clipping.title
    assert_equal entry.url, clipping.url
    assert clipping.pending?
    assert_redirected_to reader_entries_path
  end

  test "clipping the same entry twice is refused with a friendly message" do
    post clip_reader_entry_path(entries(:rails_eight)), headers: reader_headers

    assert_redirected_to reader_entries_path

    get reader_entries_path, headers: reader_headers
    assert_select ".flash--alert"

    assert_no_difference -> { Clipping.count } do
      post clip_reader_entry_path(entries(:rails_eight)), headers: reader_headers
    end
  end

  test "clipping returns to the filtered list the reader came from" do
    referer = "http://www.example.com#{reader_entries_path(feed_id: feeds(:hacker_news).id, since: 7)}"

    post clip_reader_entry_path(entries(:front_page)), headers: reader_headers.merge("Referer" => referer)

    assert_response :redirect
    assert_includes response.location, "feed_id=#{feeds(:hacker_news).id}"
    assert_includes response.location, "since=7"
  end

  test "clipping a missing entry is a 404" do
    post clip_reader_entry_path(-1), headers: reader_headers

    assert_response :not_found
  end
end
