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
    clippings = Clipping.unsent.includes(entry: :feed).to_a

    if clippings.empty?
      Rails.logger.info("[SendNewsletterJob] nothing clipped this week; skipping")
      return
    end

    subscribers = Subscriber.order(:id).to_a

    if subscribers.empty?
      Rails.logger.info("[SendNewsletterJob] no subscribers; skipping")
      return
    end

    waiting = clippings.count { |clipping| clipping.pending? || clipping.summarizing? }
    if waiting.positive? && deferrals < MAX_DEFERRALS
      Rails.logger.info("[SendNewsletterJob] #{waiting} summaries in flight; deferring")
      self.class.set(wait: DEFERRAL_WAIT).perform_later(deferrals + 1)
      return
    end

    issue = build_issue(clippings, locales_for(subscribers))
    deliver(issue, subscribers)
  end

  private

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
