# Generates the AI summary for a single clipping right after it is marked.
#
# Enqueued by Clipping#enqueue_summary_generation. The opencode run is slow and
# can fail transiently, so it is retried a few times; once the attempts run out
# the clipping is marked failed and still ships in the newsletter, just without
# a summary.
class GenerateSummaryJob < ApplicationJob
  queue_as :summaries

  MAX_ATTEMPTS = 3
  RETRY_WAIT = 30.seconds

  # Injectable so tests can supply a fake without spawning opencode. Real runs
  # (perform_later) always build the default.
  attr_writer :summary_generator

  def perform(clipping_id, attempt = 1)
    clipping = Clipping.find_by(id: clipping_id)
    return if clipping.nil?

    clipping.update!(summary_status: :summarizing)

    result = summary_generator.call(
      title: clipping.title,
      url: clipping.url,
      source: clipping.entry&.summary
    )

    clipping.apply_summary(result)
    clipping.save!
  rescue SummaryGenerator::Error, OpencodeCli::TimeoutError => e
    if attempt < MAX_ATTEMPTS
      Rails.logger.info(
        "[GenerateSummaryJob] clipping=#{clipping_id} attempt=#{attempt} failed: #{e.message}; retrying"
      )
      self.class.set(wait: attempt * RETRY_WAIT).perform_later(clipping_id, attempt + 1)
    else
      Rails.logger.warn(
        "[GenerateSummaryJob] clipping=#{clipping_id} failed after #{attempt} attempts: #{e.message}"
      )
      clipping.update(summary_status: :failed, summary_error: e.message.to_s.first(500))
    end
  end

  private

  def summary_generator
    @summary_generator ||= SummaryGenerator.new
  end
end
