require "test_helper"

class ClippingTest < ActiveSupport::TestCase
  test "requires a title and a URL" do
    clipping = Clipping.new(entry: entries(:front_page))

    assert_not clipping.valid?
    assert_includes clipping.errors.attribute_names, :title
    assert_includes clipping.errors.attribute_names, :url
  end

  test "rejects a URL that is not http(s)" do
    clipping = Clipping.new(entry: entries(:front_page), title: "t", url: "javascript:alert(1)")

    assert_not clipping.valid?
    assert_includes clipping.errors.attribute_names, :url
  end

  test "enqueues summary generation as soon as it is marked" do
    assert_enqueued_with(job: GenerateSummaryJob) do
      Clipping.create!(entry: entries(:front_page), title: "t", url: "https://example.com/x")
    end
  end

  test "starts out pending, with no summary" do
    clipping = Clipping.create!(entry: entries(:front_page), title: "t", url: "https://example.com/x")

    assert clipping.pending?
    assert_nil clipping.summary
  end

  test "refuses to queue the same entry twice while unsent" do
    existing = clippings(:queued)

    duplicate = Clipping.new(entry: existing.entry, title: existing.title, url: existing.url)
    assert_not duplicate.valid?
    assert_includes duplicate.errors.attribute_names, :entry

    # The partial unique index backs the validation up against races.
    assert_raises(ActiveRecord::RecordNotUnique) do
      Clipping.insert!({ entry_id: existing.entry_id, title: "t", url: "https://example.com/dup",
                         summary_status: "pending", created_at: Time.current, updated_at: Time.current })
    end
  end

  test "can be clipped again once the previous clipping has been sent" do
    sent = clippings(:sent)
    assert_not_nil sent.newsletter_id

    assert_difference -> { Clipping.count }, 1 do
      Clipping.create!(entry: sent.entry, title: sent.title, url: sent.url)
    end
  end

  test "unsent only returns clippings that have no issue yet" do
    assert_includes Clipping.unsent, clippings(:queued)
    assert_includes Clipping.unsent, clippings(:pending)
    assert_not_includes Clipping.unsent, clippings(:sent)
  end
end
