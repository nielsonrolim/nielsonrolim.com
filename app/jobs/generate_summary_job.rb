# Generates the AI summary for a single clipping right after it is marked.
#
# Enqueued by Clipping#enqueue_summary_generation. Before summarizing, a clipping
# that has no stored article text (the feed ones) has its page fetched, so the
# summary can cover the whole article instead of just the RSS excerpt. The
# opencode run is slow and can fail transiently, so it is retried a few times;
# once the attempts run out the clipping is marked failed and still ships in the
# newsletter, just without a summary.
#
# `overwrite` is set by the explicit "generate" button: it refreshes summaries
# that a person edited by hand, which an automatic run leaves alone.
class GenerateSummaryJob < ApplicationJob
  queue_as :summaries

  MAX_ATTEMPTS = 3
  RETRY_WAIT = 30.seconds

  # Injectable so tests can supply fakes without spawning opencode or hitting the
  # network. Real runs (perform_later) always build the defaults.
  attr_writer :summary_generator, :article_fetcher

  def perform(clipping_id, attempt = 1, overwrite = false)
    @model = model_for_attempt(attempt)
    clipping = Clipping.find_by(id: clipping_id)
    return if clipping.nil?

    clipping.update!(summary_status: :summarizing)
    fetch_full_text(clipping)

    result = summary_generator.call(
      title: clipping.display_title,
      url: clipping.primary_variant.url,
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
  # configured model, and a retry drops to the fallback. Since the primary is a
  # strong model the fallback is a safety net rather than a second opinion, so it
  # is picked for being cheap and on another provider, not for being clever.
  # Once the ladder is exhausted the last attempt stays on the fallback, so the
  # remaining retries still buy a different model rather than repeating the same
  # one.
  def model_for_attempt(attempt = 1)
    ladder = [ SummaryGenerator.configured_model, SummaryGenerator::FALLBACK_MODEL ]
    ladder[[ attempt - 1, ladder.length - 1 ].min]
  end

  # A feed clipping arrives with only the RSS excerpt as its source. Fetch the
  # page once and keep the text, so the summary covers the whole article and a
  # retry does not fetch again. A failed fetch is not fatal: the excerpt is used
  # instead, rather than failing the clipping.
  def fetch_full_text(clipping)
    return if clipping.source_text.present?

    url = clipping.primary_variant&.url
    return if url.blank?

    clipping.update!(source_text: article_fetcher.call(url).text)
  rescue ArticleFetcher::Error => e
    Rails.logger.info("[GenerateSummaryJob] clipping=#{clipping.id} could not fetch #{url}: #{e.message}")
  end

  def summary_generator
    @summary_generator ||= SummaryGenerator.new(model: @model)
  end

  def article_fetcher
    @article_fetcher ||= ArticleFetcher.new
  end
end
