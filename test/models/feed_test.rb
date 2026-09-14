require "test_helper"

class FeedTest < ActiveSupport::TestCase
  test "requires a title and a URL" do
    feed = Feed.new

    assert_not feed.valid?
    assert_includes feed.errors.attribute_names, :title
    assert_includes feed.errors.attribute_names, :url
  end

  test "rejects a URL that is not http(s)" do
    feed = Feed.new(title: "Local", url: "file:///etc/passwd")

    assert_not feed.valid?
    assert_includes feed.errors.attribute_names, :url
  end

  test "does not allow the same feed twice" do
    duplicate = Feed.new(title: "Copy", url: feeds(:ruby_blog).url)

    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :url
  end

  test "stale_before picks feeds that are due for a poll" do
    stale = Feed.stale_before(30.minutes.ago)

    assert_includes stale, feeds(:hacker_news)   # never fetched
    assert_includes stale, feeds(:broken)        # never fetched
    assert_not_includes stale, feeds(:ruby_blog) # fetched 10 minutes ago
  end

  test "tracks whether the last poll succeeded" do
    assert feeds(:ruby_blog).fetched?
    assert feeds(:ruby_blog).healthy?

    assert_not feeds(:broken).healthy?
    assert_not feeds(:hacker_news).fetched?
  end

  test "removing a feed removes its entries" do
    feed = feeds(:ruby_blog)

    assert_difference -> { Entry.count }, -feed.entries.count do
      feed.destroy
    end
  end

  test "alphabetical sorts case-insensitively" do
    Feed.create!(title: "aaa feed", url: "https://a.example.com/feed")
    Feed.create!(title: "ZZZ feed", url: "https://z.example.com/feed")

    assert_equal "aaa feed", Feed.alphabetical.first.display_title
  end

  test "alphabetical sorts by the custom title when there is one" do
    feeds(:hacker_news).update!(custom_title: "Aaa first")

    assert_equal "Aaa first", Feed.alphabetical.first.display_title
  end

  test "display_title prefers the custom title and falls back to the feed title" do
    feed = feeds(:hacker_news)

    assert_nil feed.custom_title
    assert_equal "Hacker News", feed.display_title

    feed.custom_title = "HN"
    assert_equal "HN", feed.display_title

    feed.custom_title = ""
    assert_equal "Hacker News", feed.display_title
  end

  test "a feed can have several categories" do
    feed = feeds(:ruby_blog)

    assert_equal [ "Ruby", "Web" ], feed.categories.sort_by(&:name).map(&:name)
  end

  test "a feed can be uncategorised" do
    assert_empty feeds(:broken).categories
  end

  test "removing a feed removes its category joins" do
    feed = feeds(:ruby_blog)

    assert_difference -> { FeedCategory.count }, -feed.feed_categories.count do
      assert_no_difference -> { Category.count } do
        feed.destroy
      end
    end
  end

  test "the compact add form's category field is not a column" do
    feed = Feed.new(title: "x", url: "https://x.example.com/feed", category: "Ruby")

    assert_equal "Ruby", feed.category
    assert_not_includes Feed.column_names, "category"
  end
end
