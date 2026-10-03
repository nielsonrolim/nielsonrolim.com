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
  #
  # `chain_summary` is false for that button too: it refreshes the text only, and
  # enqueuing a summary there would run the model (and overwrite the stored
  # summary) without the reader asking for it. `overwrite` rides along to the
  # chained summary so the explicit "generate summary" button, which may have to
  # fetch first, still overwrites a hand-edited summary as it promises.
  def perform(clipping_id, force: false, chain_summary: true, overwrite: false)
    clipping = Clipping.find_by(id: clipping_id)
    return if clipping.nil?

    clipping.update!(summary_status: :fetching)
    fetch_text(clipping, force: force)
  ensure
    # Never leave the clipping stuck in `fetching`: whatever happened, hand off
    # to the summary run (or the failure it will record).
    GenerateSummaryJob.perform_later(clipping_id, 1, overwrite) if clipping && chain_summary
  end

  private

  # Skips the fetch when text is already stored (a re-run, or the button firing
  # beside an automatic run), unless `force` says to replace it. The fetched
  # title replaces the host placeholder a hand-added clipping was created with,
  # so the summary runs on the real title; a title the reader typed, and a feed
  # clipping's entry title, are left alone.
  def fetch_text(clipping, force:)
    return if clipping.source_text.present? && !force

    url = clipping.primary_variant&.url
    return if url.blank?

    article = article_fetcher.call(url)
    clipping.source_text = article.text
    apply_fetched_title(clipping, article.title)
    clipping.save!
  rescue ArticleFetcher::Error => e
    Rails.logger.info(
      "[FetchSourceTextJob] clipping=#{clipping.id} could not fetch #{url}: #{e.message}"
    )
  end

  # Only a hand-added clipping is created with a stand-in title (its URL's host),
  # so only that placeholder is replaced. Everything else — the reader's typed
  # title, or a feed entry's own — is kept.
  def apply_fetched_title(clipping, title)
    return if title.blank? || !clipping.manual?

    clipping.variants.each do |variant|
      variant.title = title if variant.placeholder_title?
    end
  end

  def article_fetcher
    @article_fetcher ||= ArticleFetcher.new
  end
end
