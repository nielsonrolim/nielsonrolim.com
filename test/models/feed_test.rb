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

    assert_equal "aaa feed", Feed.alphabetical.first.title
  end
end
