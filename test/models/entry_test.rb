require "test_helper"

class EntryTest < ActiveSupport::TestCase
  test "requires a title, url and guid" do
    entry = Entry.new(feed: feeds(:ruby_blog))

    assert_not entry.valid?
    assert_equal [ :guid, :title, :url ].sort, entry.errors.attribute_names.sort
  end

  test "guid only has to be unique within a feed" do
    Entry.create!(feed: feeds(:hacker_news), guid: "shared-guid", title: "t", url: "https://example.com/a")

    assert_nothing_raised do
      Entry.create!(feed: feeds(:ruby_blog), guid: "shared-guid", title: "t", url: "https://example.com/b")
    end

    assert_raises(ActiveRecord::RecordInvalid) do
      Entry.create!(feed: feeds(:hacker_news), guid: "shared-guid", title: "t", url: "https://example.com/c")
    end
  end

  test "recent orders newest first" do
    assert_equal entries(:front_page), Entry.recent.first
  end

  test "since filters by publication date" do
    recent = Entry.since(2.days.ago)

    assert_includes recent, entries(:front_page)
    assert_includes recent, entries(:solid_queue)
    assert_not_includes recent, entries(:rails_eight)
  end

  test "clipped? only looks at clippings still waiting to be sent" do
    assert entries(:rails_eight).clipped?
    assert_not entries(:front_page).clipped?
  end

  test "clipped? becomes true again once a new clipping is queued" do
    entry = entries(:front_page)
    assert_not entry.clipped?

    Clipping.create!(entry: entry, title: entry.title, url: entry.url)

    assert entry.clipped?
  end

  test "clipped? answers from a preloaded association without querying" do
    entry = Entry.includes(:clippings).find(entries(:rails_eight).id)
    other = Entry.includes(:clippings).find(entries(:front_page).id)

    assert_predicate entry, :clipped?
    assert_not_predicate other, :clipped?

    assert_no_queries do
      assert_predicate entry, :clipped?
      assert_not_predicate other, :clipped?
    end
  end

  test "clipped? queries when the association was not preloaded" do
    entry = Entry.find(entries(:rails_eight).id)

    assert_queries_match(/SELECT/) { assert_predicate entry, :clipped? }
  end
end
