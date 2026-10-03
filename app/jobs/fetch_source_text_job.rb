# Fetches the text a clipping's summary is generated from, off the request
# cycle.
#
# Adding a clipping by URL used to fetch the page inline, which for a YouTube
# video means resolving the watch page, its caption tracks, and then a `yt-dlp`
# subprocess that retries rate limits per language — minutes of work held open
# in the HTTP request. Now the request only creates the clipping and enqueues
# this job; the reader sees "fetching" while it runs, and the summary is
# enqueued once the text is stored.
#
# The fetch is best-effort, exactly as before: a page that cannot be fetched
# leaves the clipping with whatever source it has (nothing for a manual URL, the
# RSS excerpt for a feed clipping) rather than failing it. Only a clipping with
# neither text nor excerpt is marked failed, because there is nothing to
# summarize. Either way the summary job is enqueued, so the clipping always
# moves forward and is never left stuck in `fetching`.
class FetchSourceTextJob < ApplicationJob
  queue_as :sources

  # Injectable so tests can supply a fake without hitting the network. Real runs
  # (perform_later) build the default.
  attr_writer :article_fetcher

  # `force` re-fetches even when text is already stored: the explicit "fetch text
  # again" button, which must not skip on the existing text.
  def perform(clipping_id, force: false)
    clipping = Clipping.find_by(id: clipping_id)
    return if clipping.nil?

    clipping.update!(summary_status: :fetching)
    fetch_text(clipping, force: force)
  ensure
    # Never leave the clipping stuck in `fetching`: whatever happened, hand off
    # to the summary run (or the failure it will record).
    GenerateSummaryJob.perform_later(clipping_id) if clipping
  end

  private

  # Skips the fetch when text is already stored (a re-run, or the button firing
  # beside an automatic run), unless `force` says to replace it.
  def fetch_text(clipping, force:)
    return if clipping.source_text.present? && !force

    url = clipping.primary_variant&.url
    return if url.blank?

    clipping.update!(source_text: article_fetcher.call(url).text)
  rescue ArticleFetcher::Error => e
    Rails.logger.info(
      "[FetchSourceTextJob] clipping=#{clipping.id} could not fetch #{url}: #{e.message}"
    )
  end

  def article_fetcher
    @article_fetcher ||= ArticleFetcher.new
  end
end
