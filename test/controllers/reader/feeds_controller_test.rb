require "test_helper"

class Reader::FeedsControllerTest < ActionDispatch::IntegrationTest
  setup do
    set_reader_credentials!
    @xml = file_fixture("sample_feed.xml").read
    @original_transport = FeedFetcher.default_transport
    FeedFetcher.default_transport = transport_always(http_response(200, @xml))
  end

  teardown do
    FeedFetcher.default_transport = @original_transport
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
    assert_equal "ruby", feed.category
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
    assert_select ".flash--alert", /já está cadastrada/
  end

  test "adding a broken feed reports the error" do
    FeedFetcher.default_transport = transport_always(http_response(503, "unavailable"))

    assert_no_difference -> { Feed.count } do
      post reader_feeds_path, params: { feed: { url: "https://down.example.com/feed" } }, headers: reader_headers
    end

    get reader_feeds_path, headers: reader_headers
    assert_select ".flash--alert", /Não foi possível ler o feed/
  end

  test "adding a URL that is not a feed reports the error" do
    FeedFetcher.default_transport = transport_always(http_response(200, "<html>not a feed</html>"))

    assert_no_difference -> { Feed.count } do
      post reader_feeds_path, params: { feed: { url: "https://example.com/" } }, headers: reader_headers
    end

    get reader_feeds_path, headers: reader_headers
    assert_select ".flash--alert"
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
    FeedFetcher.default_transport = transport_always(http_response(503, "unavailable"))
    feed = feeds(:ruby_blog)
    polled_at = feed.last_fetched_at

    post refresh_reader_feed_path(feed), headers: reader_headers

    assert_redirected_to reader_feeds_path
    feed.reload
    assert_equal polled_at, feed.last_fetched_at
    assert_match(/503/, feed.last_error)

    get reader_feeds_path, headers: reader_headers
    assert_select ".flash--alert", /Falha ao atualizar/
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
end
