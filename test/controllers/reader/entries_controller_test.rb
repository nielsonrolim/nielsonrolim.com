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
    entry = entries(:rails_eight)
    get reader_entries_path, headers: reader_headers

    assert_response :success
    assert_select "body", /na próxima edição/
    assert_select "#clip_entry_#{entry.id}"
    assert_select "form[action=?]", unclip_reader_entry_path(entry)
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
    assert_equal entry.title, clipping.display_title
    assert_equal entry.url, clipping.primary_variant.url
    assert_nil clipping.primary_variant.locale
    assert clipping.pending?
    assert_redirected_to reader_entries_path
  end

  test "clipping the same entry twice is refused with a friendly message" do
    post clip_reader_entry_path(entries(:rails_eight)), headers: reader_headers

    assert_redirected_to reader_entries_path

    get reader_entries_path, headers: reader_headers
    assert_select ".toast--alert"

    assert_no_difference -> { Clipping.count } do
      post clip_reader_entry_path(entries(:rails_eight)), headers: reader_headers
    end
  end

  test "clipping an entry answers with a Turbo Stream instead of a redirect" do
    entry = entries(:front_page)

    assert_difference -> { Clipping.count }, 1 do
      post clip_reader_entry_path(entry),
           headers: reader_headers.merge("Accept" => Mime[:turbo_stream].to_s)
    end

    assert_turbo_stream action: "replace", target: "clip_entry_#{entry.id}" do
      assert_select "#clip_entry_#{entry.id}" # id kept, so the next replace lands
      assert_select "span", /na próxima edição/
    end

    assert_turbo_stream action: "append", target: "toasts" do
      assert_select "p.toast--notice", /#{Regexp.escape(entry.title)}/
    end
  end

  test "a refused clip over Turbo Stream appends an alert toast" do
    entry = entries(:rails_eight) # already queued in the fixtures

    assert_no_difference -> { Clipping.count } do
      post clip_reader_entry_path(entry),
           headers: reader_headers.merge("Accept" => Mime[:turbo_stream].to_s)
    end

    assert_turbo_stream action: "append", target: "toasts" do
      assert_select "p.toast--alert", /marcar/
    end
    assert_no_turbo_stream action: "replace"
  end

  test "unclipping an entry removes it from the queue over Turbo Stream" do
    entry = entries(:rails_eight) # queued in the fixtures

    assert_difference -> { Clipping.count }, -1 do
      delete unclip_reader_entry_path(entry),
             headers: reader_headers.merge("Accept" => Mime[:turbo_stream].to_s)
    end

    assert_not entry.reload.clipped?

    assert_turbo_stream action: "replace", target: "clip_entry_#{entry.id}" do
      assert_select "#clip_entry_#{entry.id}" # id kept, so the next clip lands
      assert_select "form[action=?]", clip_reader_entry_path(entry)
    end
    assert_turbo_stream action: "append", target: "toasts" do
      assert_select "p.toast--notice", /Removido da próxima edição/
    end
  end

  test "unclipping via plain HTML redirects back with a notice" do
    entry = entries(:rails_eight)

    assert_difference -> { Clipping.count }, -1 do
      delete unclip_reader_entry_path(entry), headers: reader_headers
    end

    assert_redirected_to reader_entries_path
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

  test "the feed picker is grouped by category and shows display titles" do
    get reader_entries_path, headers: reader_headers

    assert_response :success
    picker = css_select("details").map(&:text).join
    assert_includes picker, "Ruby"
    assert_includes picker, "News"
    assert_includes picker, "Web"
    assert_includes picker, "Ruby Weekly (curadoria)"
    assert_includes picker, "sem categoria"
  end

  test "a feed with two categories appears under each of them" do
    get reader_entries_path, headers: reader_headers

    assert_equal 2, css_select("details").text.scan("Ruby Weekly (curadoria)").size
  end

  test "filters entries by category" do
    get reader_entries_path, params: { category_id: categories(:ruby).id }, headers: reader_headers

    assert_response :success
    assert_select "body", /Solid Queue internals/
    assert_select "body", text: /Show HN/, count: 0
  end

  test "combines the category filter with a time window" do
    get reader_entries_path, params: { category_id: categories(:ruby).id, since: 1 }, headers: reader_headers

    assert_response :success
    assert_select "body", /Solid Queue internals/          # 20 hours ago
    assert_select "body", text: /Rails 8\.1 ships/, count: 0 # 3 days ago
  end

  test "a filter link keeps the other active filters" do
    get reader_entries_path, params: { feed_id: feeds(:ruby_blog).id, since: 7 }, headers: reader_headers

    assert_response :success
    assert_select "a[href*=?][href*=?]", "category_id=#{categories(:ruby).id}", "feed_id=#{feeds(:ruby_blog).id}"
    assert_select "a[href*=?][href*=?]", "category_id=#{categories(:ruby).id}", "since=7"
  end

  test "an unknown category filter is ignored" do
    get reader_entries_path, params: { category_id: -1 }, headers: reader_headers

    assert_response :success
    assert_select "body", /Solid Queue internals/
  end
end
