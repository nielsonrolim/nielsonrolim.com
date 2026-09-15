require "test_helper"

class Reader::FeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    set_reader_credentials!
    @xml = file_fixture("sample_feed.xml").read
    @original_transport = HttpTransport.default
    HttpTransport.default = transport_always(http_response(200, @xml))
  end

  teardown do
    HttpTransport.default = @original_transport
    restore_reader_credentials!
  end

  test "lists the feeds with their entry counts and last poll" do
    get reader_feeds_path, headers: reader_headers

    assert_response :success
    assert_select "body", /Ruby Weekly/
    assert_select "body", /Hacker News/
    assert_select "body", /2 entradas/     # ruby_blog has two entries
    assert_select "body", /nunca consultada/
  end

  test "surfaces a feed that is failing" do
    get reader_feeds_path, headers: reader_headers

    assert_response :success
    assert_select ".text-err", /HTTP 503/
  end

  test "adding a feed learns its title from the feed itself" do
    assert_difference -> { Feed.count }, 1 do
      assert_enqueued_with(job: RefreshFeedsJob) do
        post reader_feeds_path, params: { feed: { url: "https://example.com/feed.xml", category: "ruby" } },
                                headers: reader_headers
      end
    end

    feed = Feed.last
    assert_equal "Ruby & Rails Weekly", feed.title
    assert_equal "https://example.com", feed.site_url
    # Reuses the existing "Ruby" category rather than creating a "ruby" one.
    assert_equal [ "Ruby" ], feed.categories.map(&:name)
    assert_redirected_to reader_feeds_path
  end

  test "adding a feed imports its entries" do
    # The import job is enqueued by the create action, so it has to be performed
    # inside the block to be picked up.
    perform_enqueued_jobs(only: RefreshFeedsJob) do
      post reader_feeds_path, params: { feed: { url: "https://example.com/feed.xml" } }, headers: reader_headers
    end

    assert_equal 3, Feed.find_by(url: "https://example.com/feed.xml").entries.count
  end

  test "adding a feed twice is refused" do
    assert_no_difference -> { Feed.count } do
      post reader_feeds_path, params: { feed: { url: feeds(:ruby_blog).url } }, headers: reader_headers
    end

    get reader_feeds_path, headers: reader_headers
    assert_select ".toast--alert", /já está cadastrada/
  end

  test "adding a broken feed reports the error" do
    HttpTransport.default = transport_always(http_response(503, "unavailable"))

    assert_no_difference -> { Feed.count } do
      post reader_feeds_path, params: { feed: { url: "https://down.example.com/feed" } }, headers: reader_headers
    end

    get reader_feeds_path, headers: reader_headers
    assert_select ".toast--alert", /Não foi possível ler o feed/
  end

  test "adding a URL that is not a feed reports the error" do
    HttpTransport.default = transport_always(http_response(200, "<html>not a feed</html>"))

    assert_no_difference -> { Feed.count } do
      post reader_feeds_path, params: { feed: { url: "https://example.com/" } }, headers: reader_headers
    end

    get reader_feeds_path, headers: reader_headers
    assert_select ".toast--alert"
  end

  test "a missing URL is rejected" do
    assert_no_difference -> { Feed.count } do
      post reader_feeds_path, params: { feed: { url: "" } }, headers: reader_headers
    end

    assert_response :redirect
  end

  test "refreshing one feed imports its entries" do
    feed = feeds(:hacker_news)

    assert_difference -> { feed.entries.count }, 3 do
      post refresh_reader_feed_path(feed), headers: reader_headers
    end

    assert_redirected_to reader_feeds_path
    assert_not_nil feed.reload.last_fetched_at
  end

  test "refreshing a failing feed reports the error and keeps the old poll time" do
    HttpTransport.default = transport_always(http_response(503, "unavailable"))
    feed = feeds(:ruby_blog)
    polled_at = feed.last_fetched_at

    post refresh_reader_feed_path(feed), headers: reader_headers

    assert_redirected_to reader_feeds_path
    feed.reload
    assert_equal polled_at, feed.last_fetched_at
    assert_match(/503/, feed.last_error)

    get reader_feeds_path, headers: reader_headers
    assert_select ".toast--alert", /Falha ao atualizar/
  end

  test "refresh all queues the job" do
    assert_enqueued_with(job: RefreshFeedsJob) do
      post refresh_all_reader_feeds_path, headers: reader_headers
    end

    assert_redirected_to reader_feeds_path
  end

  test "removing a feed removes its entries" do
    feed = feeds(:ruby_blog)
    entries = feed.entries.count

    assert_difference -> { Feed.count }, -1 do
      assert_difference -> { Entry.count }, -entries do
        delete reader_feed_path(feed), headers: reader_headers
      end
    end

    assert_redirected_to reader_feeds_path
  end

  test "an unconfigured reader is closed rather than open" do
    without_reader_credentials do
      get reader_feeds_path

      assert_response :forbidden
    end
  end

  test "the edit page shows the URL as text, never as an input" do
    feed = feeds(:ruby_blog)

    get edit_reader_feed_path(feed), headers: reader_headers

    assert_response :success
    assert_select "p", /#{Regexp.escape(feed.url)}/
    assert_select "input[name=?]", "feed[url]", count: 0
    assert_select "input[type=checkbox][name=?]", "feed[category_ids][]"
  end

  test "the edit page checks the feed's current categories" do
    feed = feeds(:ruby_blog)

    get edit_reader_feed_path(feed), headers: reader_headers

    assert_response :success
    assert_select "input[type=checkbox][name=?][value=?][checked]", "feed[category_ids][]", categories(:ruby).id
    assert_select "input[type=checkbox][name=?][value=?][checked]", "feed[category_ids][]", categories(:web).id
    assert_select "input[type=checkbox][name=?][value=?][checked]", "feed[category_ids][]", categories(:news).id, count: 0
  end

  test "updating sets the display title while keeping the feed's own title" do
    feed = feeds(:hacker_news)

    patch reader_feed_path(feed), params: { feed: { custom_title: "HN" } }, headers: reader_headers

    assert_redirected_to reader_feeds_path
    feed.reload
    assert_equal "HN", feed.custom_title
    assert_equal "HN", feed.display_title
    assert_equal "Hacker News", feed.title
  end

  test "updating can clear the custom title" do
    feed = feeds(:ruby_blog)
    assert_equal "Ruby Weekly (curadoria)", feed.display_title

    patch reader_feed_path(feed), params: { feed: { custom_title: "" } }, headers: reader_headers

    assert_equal "Ruby Weekly", feed.reload.display_title
  end

  test "updating replaces the whole category set" do
    feed = feeds(:broken)

    patch reader_feed_path(feed),
          params: { feed: { category_ids: [ categories(:ruby).id.to_s, categories(:news).id.to_s ] } },
          headers: reader_headers

    assert_equal [ "News", "Ruby" ], feed.reload.categories.map(&:name).sort
  end

  test "unchecking a category removes it" do
    feed = feeds(:ruby_blog)
    assert_equal [ "Ruby", "Web" ], feed.categories.map(&:name).sort

    patch reader_feed_path(feed),
          params: { feed: { category_ids: [ categories(:ruby).id.to_s ] } },
          headers: reader_headers

    assert_equal [ "Ruby" ], feed.reload.categories.map(&:name)
  end

  test "categories typed into the new-category field are created and attached" do
    feed = feeds(:broken)

    assert_difference -> { Category.count }, 2 do
      patch reader_feed_path(feed),
            params: { feed: { new_categories: "Linux,  Rust " } },
            headers: reader_headers
    end

    assert_equal [ "Linux", "Rust" ], feed.reload.categories.map(&:name).sort
  end

  test "a new category that already exists is reused, not duplicated" do
    feed = feeds(:broken)

    assert_no_difference -> { Category.count } do
      patch reader_feed_path(feed),
            params: { feed: { new_categories: "ruby" } },
            headers: reader_headers
    end

    assert_equal [ categories(:ruby).id ], feed.reload.category_ids
  end

  test "an unknown category id is ignored rather than raising" do
    feed = feeds(:broken)

    patch reader_feed_path(feed), params: { feed: { category_ids: [ "999999" ] } }, headers: reader_headers

    assert_redirected_to reader_feeds_path
    assert_empty feed.reload.categories
  end

  test "the URL cannot be changed through update" do
    feed = feeds(:hacker_news)

    patch reader_feed_path(feed),
          params: { feed: { url: "https://evil.example.com/feed" } },
          headers: reader_headers

    assert_equal "https://news.ycombinator.com/rss", feed.reload.url
  end

  test "a validation failure re-renders the form and rolls the categories back" do
    feed = feeds(:ruby_blog)
    feed.update_column(:title, "") # bypass validation to leave an invalid row

    patch reader_feed_path(feed),
          params: { feed: { category_ids: [ categories(:news).id.to_s ] } },
          headers: reader_headers

    assert_response :unprocessable_content
    assert_select ".toast--alert"
    assert_equal [ "Ruby", "Web" ], feed.reload.categories.map(&:name).sort
  end

  test "the refresh-all button shows its label, not a raw translation hash" do
    get reader_feeds_path, headers: reader_headers

    assert_response :success
    assert_select "form button", /atualizar todas/
    # Regression: the label and the flash used to share a duplicate
    # `refresh_all` key, and YAML kept the hash, so the button rendered
    # `{queued: "…"}`.
    assert_select "body", text: /\{queued:/, count: 0
  end

  test "renders the category filter links" do
    get reader_feeds_path, headers: reader_headers

    assert_response :success
    assert_select "a[href=?]", reader_feeds_path(category_id: categories(:ruby).id)
    assert_select "a[href=?]", reader_feeds_path(category_id: categories(:news).id)
    assert_select "a[href=?]", reader_feeds_path(uncategorised: 1)
    assert_select "a[href=?]", reader_feeds_path
  end

  test "filters the list by category" do
    get reader_feeds_path, params: { category_id: categories(:news).id }, headers: reader_headers

    assert_response :success
    assert_select "body", /Hacker News/
    assert_select "body", text: /Ruby Weekly/, count: 0
  end

  test "a feed with the category shows up under it" do
    get reader_feeds_path, params: { category_id: categories(:web).id }, headers: reader_headers

    assert_response :success
    assert_select "body", /Ruby Weekly/
    assert_select "body", text: /Hacker News/, count: 0
  end

  test "filters to the feeds that carry no category" do
    get reader_feeds_path, params: { uncategorised: 1 }, headers: reader_headers

    assert_response :success
    assert_select "body", /Broken Feed/
    assert_select "body", text: /Hacker News/, count: 0
    assert_select "body", text: /Ruby Weekly/, count: 0
  end

  test "an unknown category filter falls back to the full list" do
    get reader_feeds_path, params: { category_id: -1 }, headers: reader_headers

    assert_response :success
    assert_select "body", /Broken Feed/
    assert_select "body", /Hacker News/
    assert_select "body", /Ruby Weekly/
  end

  test "says so when a category has no feeds" do
    empty = Category.create!(name: "Vazia")

    get reader_feeds_path, params: { category_id: empty.id }, headers: reader_headers

    assert_response :success
    assert_select "body", /Nenhuma fonte nesta categoria/
    assert_select "body", text: /Nenhuma fonte cadastrada/, count: 0
  end

  test "the unfiltered list still says nothing is subscribed when there are no feeds" do
    Feed.destroy_all

    get reader_feeds_path, headers: reader_headers

    assert_response :success
    assert_select "body", /Nenhuma fonte cadastrada/
  end
end
