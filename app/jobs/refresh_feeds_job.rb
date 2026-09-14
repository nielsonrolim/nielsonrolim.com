# Polls every feed that is due for a refresh and stores any new entries.
# Scheduled from config/recurring.yml.
class RefreshFeedsJob < ApplicationJob
  queue_as :feeds

  # Injectable so tests can serve canned feed bodies without the network.
  attr_writer :transport

  def perform(limit = nil)
    results = FeedFetcher.refresh_due(limit: limit, transport: transport)

    succeeded = results.count(&:success?)
    failed = results.size - succeeded

    Rails.logger.info(
      "[RefreshFeedsJob] polled=#{results.size} ok=#{succeeded} failed=#{failed} " \
      "new_entries=#{results.sum(&:new_entries)}"
    )

    results.reject(&:success?).each do |result|
      Rails.logger.warn("[RefreshFeedsJob] #{result.feed&.url}: #{result.error}")
    end

    results
  end

  private

  def transport
    @transport ||= HttpTransport.default
  end
end
