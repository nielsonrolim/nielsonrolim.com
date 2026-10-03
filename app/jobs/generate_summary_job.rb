# Generates the AI summary for a single clipping.
#
# Enqueued by FetchSourceTextJob once the clipping's source text has been
# fetched (the fetch itself is a separate job, because for a YouTube video it
# can take minutes). The opencode run is slow and can fail transiently, so it is
# retried a few times; once the attempts run out the clipping is marked failed
# and still ships in the newsletter, just without a summary.
#
# `overwrite` is set by the explicit "generate" button: it refreshes summaries
# that a person edited by hand, which an automatic run leaves alone.
class GenerateSummaryJob < ApplicationJob
  queue_as :summaries

  MAX_ATTEMPTS = 3
  RETRY_WAIT = 30.seconds

  # Injectable so tests can supply a fake without spawning opencode. Real runs
  # (perform_later) always build the default.
  attr_writer :summary_generator

  def perform(clipping_id, attempt = 1, overwrite = false)
    @model = model_for_attempt(attempt)
    clipping = Clipping.find_by(id: clipping_id)
    return if clipping.nil?

    clipping.update!(summary_status: :summarizing)

    result = summary_generator.call(
      title: clipping.display_title,
      url: clipping.primary_variant&.url,
      source: clipping.summary_source,
      source_partial: clipping.partial_summary_source?
    )

    clipping.apply_summary(result, overwrite: overwrite)
    clipping.save!
  rescue SummaryGenerator::Error, OpencodeCli::TimeoutError => e
    if attempt < MAX_ATTEMPTS
      Rails.logger.info(
        "[GenerateSummaryJob] clipping=#{clipping_id} model=#{@model} attempt=#{attempt} " \
        "failed: #{e.message}; retrying with #{model_for_attempt(attempt + 1)}"
      )
      self.class.set(wait: attempt * RETRY_WAIT).perform_later(clipping_id, attempt + 1, overwrite)
    else
      Rails.logger.warn(
        "[GenerateSummaryJob] clipping=#{clipping_id} model=#{@model} failed after " \
        "#{attempt} attempts: #{e.message}"
      )
      clipping.update(summary_status: :failed, summary_error: e.message.to_s.first(500))
    end
  end

  private

  # The job's own attempts double as a model ladder: the first run uses the
  # configured free model, and a retry uses paid Terra. The fallback is a safety
  # net for failed runs, not a second opinion on the quality of a valid summary.
  # Both use Zen, so a provider-wide failure can affect both. The final attempt
  # stays on Terra rather than returning to the failed primary.
  def model_for_attempt(attempt = 1)
    ladder = [ SummaryGenerator.configured_model, SummaryGenerator::FALLBACK_MODEL ]
    ladder[[ attempt - 1, ladder.length - 1 ].min]
  end

  def summary_generator
    @summary_generator ||= SummaryGenerator.new(model: @model)
  end
end
