# Builds the weekly clipping issue from every clipping that has not been sent
# yet and emails it to all subscribers.
#
# Scheduled from config/recurring.yml (weekly). Can also be triggered by hand
# from the reader UI.
class SendNewsletterJob < ApplicationJob
  queue_as :newsletters

  # If some clippings are still waiting on their summary, postpone rather than
  # ship a half-written issue — but only up to a point, so a stuck summary can
  # never block the newsletter forever.
  MAX_DEFERRALS = 6
  DEFERRAL_WAIT = 10.minutes

  # Injectable so tests can make delivery blow up without sending email.
  attr_writer :mailer

  def perform(deferrals = 0)
    # Shippable only: a clipping whose summary failed has nothing to show, and a
    # deferred one is held out of this issue; both wait for a later one.
    clippings = Clipping.shippable.includes(entry: :feed).to_a

    if clippings.empty?
      # No issue this week, but the week still passes for a held clipping: it
      # comes back in line for the next run.
      release_deferrals
      Rails.logger.info("[SendNewsletterJob] nothing clipped this week; skipping")
      return
    end

    subscribers = Subscriber.order(:id).to_a

    if subscribers.empty?
      Rails.logger.info("[SendNewsletterJob] no subscribers; skipping")
      return
    end

    # `fetching` counts too: the text is still being fetched, so the summary (and
    # therefore the clipping) is not ready — shipping now would drop it.
    waiting = clippings.count(&:in_flight?)
    if waiting.positive? && deferrals < MAX_DEFERRALS
      # Same issue being postponed: do NOT release deferrals here, or a held
      # clipping would slip into this issue on the retry.
      Rails.logger.info("[SendNewsletterJob] #{waiting} summaries in flight; deferring")
      self.class.set(wait: DEFERRAL_WAIT).perform_later(deferrals + 1)
      return
    end

    issue = build_issue(clippings, locales_for(subscribers))
    release_deferrals
    deliver(issue, subscribers)
  end

  private

  # A deferred clipping skips exactly one issue: once that issue is built — or
  # there was nothing to ship this week — the hold is lifted so it can go out in
  # the following one. Never called on the in-flight reschedule, so a held
  # clipping cannot slip into the retry of the same issue.
  def release_deferrals
    Clipping.unsent.deferred.update_all(deferred_at: nil) # rubocop:disable Rails/SkipsModelValidations
  end

  # One rendered version per language the issue has to go out in, so a body is
  # only composed for languages that are actually subscribed.
  def locales_for(subscribers)
    subscribers.map(&:language).uniq
  end

  def build_issue(clippings, locales)
    Newsletter.transaction do
      issue = Newsletter.create!(status: :sending)

      locales.each do |locale|
        composer = NewsletterComposer.new(clippings, date: Time.current, locale: locale)
        issue.bodies.create!(
          locale: locale,
          subject: composer.subject,
          body: composer.to_html,
          body_text: composer.to_text
        )
      end

      # Claim the clippings for this issue so the next run cannot re-send them.
      Clipping.where(id: clippings.map(&:id)).update_all(newsletter_id: issue.id) # rubocop:disable Rails/SkipsModelValidations

      issue
    end
  end

  def deliver(issue, subscribers)
    subscribers.group_by(&:language).each do |locale, group|
      body = issue.body_for(locale)
      group.each { |subscriber| mailer.issue(newsletter: issue, subscriber: subscriber, body: body).deliver_later }
    end

    issue.update!(status: :sent, sent_at: Time.current, recipient_count: subscribers.size)

    Rails.logger.info(
      "[SendNewsletterJob] sent issue ##{issue.id} (#{issue.clippings.count} clippings) " \
      "to #{subscribers.size} subscribers in #{issue.locales.join(", ")}"
    )
  rescue StandardError
    issue.update(status: :failed)
    raise
  end

  def mailer
    @mailer ||= NewsletterMailer
  end
end
