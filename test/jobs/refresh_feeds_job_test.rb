require "test_helper"

class RefreshFeedsJobTest < ActiveJob::TestCase
  setup do
    @xml = file_fixture("sample_feed.xml").read
  end

  test "imports entries for every feed that is due" do
    job = job_with(transport_always(http_response(200, @xml)))
    fresh_before = feeds(:ruby_blog).last_fetched_at

    # hacker_news and broken were never fetched; ruby_blog was fetched 10 min ago.
    results = nil
    assert_difference -> { Entry.count }, 6 do
      results = job.perform_now
    end

    assert_equal 2, results.size
    assert(results.all?(&:success?))
    assert_equal 6, results.sum(&:new_entries)
    assert_not_nil feeds(:hacker_news).reload.last_fetched_at
    # The feed that is still fresh was left alone.
    assert_equal fresh_before, feeds(:ruby_blog).reload.last_fetched_at
  end

  test "keeps going when one feed fails" do
    responses = {
      "https://news.ycombinator.com/rss" => http_response(200, @xml),
      "https://broken.example.com/feed" => http_response(503, "unavailable")
    }
    transport = HttpTransport.new(session: ->(uri) { responses.fetch(uri.to_s) })

    results = job_with(transport).perform_now

    assert_equal 2, results.size
    assert_equal 1, results.count(&:success?)
    assert_match(/503/, feeds(:broken).reload.last_error)
    assert_nil feeds(:broken).last_fetched_at
  end

  test "honours a limit so a big run can be throttled" do
    results = job_with(transport_always(http_response(200, @xml)), limit: 1).perform_now

    assert_equal 1, results.size
  end

  test "does nothing when every feed is fresh" do
    Feed.update_all(last_fetched_at: Time.current) # rubocop:disable Rails/SkipsModelValidations

    results = job_with(transport_always(http_response(200, @xml))).perform_now

    assert_empty results
  end

  private

  def job_with(transport, limit: nil)
    job = RefreshFeedsJob.new(limit)
    job.transport = transport
    job
  end
end
