require "test_helper"

class SendNewsletterJobTest < ActiveJob::TestCase
  include ActionMailer::TestHelper

  # Stands in for NewsletterMailer when delivery must blow up.
  class FailingMailer
    class Delivery
      def deliver_later
        raise "smtp is down"
      end
    end

    def issue(newsletter:, subscriber:, body: nil)
      Delivery.new
    end
  end

  test "sends an issue to every subscriber and archives it" do
    make_all_summaries_ready

    assert_difference -> { Newsletter.count }, 1 do
      assert_enqueued_emails 2 do
        SendNewsletterJob.perform_now
      end
    end

    issue = Newsletter.last
    assert issue.sent?
    assert_not_nil issue.sent_at
    assert_equal 2, issue.recipient_count
    assert_equal [ clippings(:queued), clippings(:pending) ].sort_by(&:id), issue.clippings.sort_by(&:id)
    assert_empty Clipping.unsent

    # Each language's body carries that language's title and summary.
    assert_includes issue.body_for("pt-BR").body, "O Rails 8.1 traz uma nova interface de filas"
    assert_includes issue.body_for("en-US").body, "Rails 8.1 ships with a new queue UI"
    assert_includes issue.body_text, "https://example.com/solid-queue"
    assert_equal NewsletterComposer.subject_for(issue.created_at), issue.subject
  end

  test "skips when nothing has been clipped" do
    Clipping.unsent.destroy_all

    assert_no_difference -> { Newsletter.count } do
      assert_no_enqueued_jobs { SendNewsletterJob.perform_now }
    end
  end

  test "skips when there is nobody to send to" do
    Subscriber.delete_all
    make_all_summaries_ready

    assert_no_difference -> { Newsletter.count } do
      assert_no_enqueued_jobs { SendNewsletterJob.perform_now }
    end

    # The clippings stay queued for the next issue.
    assert_equal 2, Clipping.unsent.count
  end

  test "defers while summaries are still being generated" do
    assert clippings(:pending).pending?

    assert_no_difference -> { Newsletter.count } do
      assert_enqueued_with(job: SendNewsletterJob, args: [ 1 ]) do
        SendNewsletterJob.new(0).perform_now
      end
    end

    assert_no_enqueued_emails
    assert_equal 2, Clipping.unsent.count
  end

  test "stops deferring once the limit is reached and ships what it has" do
    assert_difference -> { Newsletter.count }, 1 do
      assert_enqueued_emails 2 do
        SendNewsletterJob.new(SendNewsletterJob::MAX_DEFERRALS).perform_now
      end
    end

    issue = Newsletter.last
    assert issue.sent?
    assert_includes issue.clippings, clippings(:pending)
    # A clipping whose summary never arrived still ships, without one.
    assert_nil issue.clippings.find(clippings(:pending).id).summary_for("pt-BR")
  end

  test "ignores clippings that already went out" do
    make_all_summaries_ready
    SendNewsletterJob.perform_now

    assert_not_includes Newsletter.last.clippings, clippings(:sent)
  end

  test "marks the issue failed when delivery raises" do
    make_all_summaries_ready

    job = SendNewsletterJob.new
    job.mailer = FailingMailer.new

    assert_raises(RuntimeError) { job.perform_now }

    issue = Newsletter.last
    assert issue.failed?
    assert_nil issue.sent_at
    assert_equal 0, issue.recipient_count
  end

  test "an empty week never produces an issue" do
    Clipping.unsent.destroy_all

    assert_no_difference -> { Newsletter.count } do
      SendNewsletterJob.perform_now(SendNewsletterJob::MAX_DEFERRALS)
    end
  end

  test "composes one body per language the subscribers read" do
    make_all_summaries_ready

    SendNewsletterJob.perform_now

    issue = Newsletter.last
    assert_equal %w[en-US pt-BR], issue.locales.sort
    # Each body is rendered in its own language.
    assert_includes issue.body_for("pt-BR").body, "valeu a leitura"
    assert_includes issue.body_for("en-US").body, "Worth reading this week"
  end

  test "only composes the languages that are actually subscribed" do
    Subscriber.where(language: "en-US").destroy_all
    make_all_summaries_ready

    SendNewsletterJob.perform_now

    assert_equal [ "pt-BR" ], Newsletter.last.locales
  end

  test "sends each subscriber the body in their language" do
    make_all_summaries_ready
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
      SendNewsletterJob.perform_now
    end

    by_recipient = ActionMailer::Base.deliveries.index_by { |email| email.to.first }

    portuguese = by_recipient.fetch(subscribers(:first).email)
    english = by_recipient.fetch(subscribers(:second).email)

    assert_includes portuguese.html_part.body.to_s, "valeu a leitura"
    assert_includes english.html_part.body.to_s, "Worth reading this week"
    assert_not_includes english.html_part.body.to_s, "valeu a leitura"
  end

  test "links each subscriber to the right edition of every clipping" do
    make_all_summaries_ready
    # A bilingual story: en-US and pt-BR each have their own edition.
    clippings(:queued).variant_for("pt-BR").update!(url: "https://example.com/rails-8-1-pt")

    # An en-US-only story: pt-BR is just a translation, with no URL of its own.
    en_only = Clipping.new(source_name: "dev.to", summary_status: :summarized)
    en_only.variants.build(locale: "en-US", url: "https://dev.to/brewwi", origin: :generated,
                           title: "BrewUI: A First Look", summary: "BrewUI is a native macOS app.")
    en_only.variants.build(locale: "pt-BR", origin: :generated,
                           title: "BrewUI: Um Primeiro Olhar", summary: "BrewUI é um aplicativo nativo.")
    en_only.save!
    ActionMailer::Base.deliveries.clear

    perform_enqueued_jobs(only: ActionMailer::MailDeliveryJob) do
      SendNewsletterJob.perform_now
    end

    by_recipient = ActionMailer::Base.deliveries.index_by { |email| email.to.first }
    portuguese = by_recipient.fetch(subscribers(:first).email).html_part.body.to_s
    english = by_recipient.fetch(subscribers(:second).email).html_part.body.to_s

    # Bilingual clipping: each language links to its own edition.
    assert_includes english, "https://example.com/rails-8-1"
    assert_not_includes english, "https://example.com/rails-8-1-pt"
    assert_includes portuguese, "https://example.com/rails-8-1-pt"

    # pt-BR-only clipping: both languages fall back to the pt-BR edition.
    assert_includes english, "https://example.com/solid-queue"
    assert_includes portuguese, "https://example.com/solid-queue"

    # en-US-only clipping: both languages fall back to the en-US edition.
    assert_includes english, "https://dev.to/brewwi"
    assert_includes english, "BrewUI: A First Look"
    assert_includes portuguese, "https://dev.to/brewwi"
    assert_includes portuguese, "BrewUI: Um Primeiro Olhar"
  end

  test "leaves a clipping whose summary failed out of the issue" do
    make_all_summaries_ready
    clippings(:pending).update!(summary_status: :failed, summary_error: "sem fonte")

    assert_difference -> { Newsletter.count }, 1 do
      SendNewsletterJob.perform_now
    end

    issue = Newsletter.last
    assert_equal [ clippings(:queued).id ], issue.clippings.map(&:id)
    # It stays in the queue, waiting to be fixed.
    assert_includes Clipping.unsent, clippings(:pending)
  end

  test "creates no issue when every clipping failed" do
    make_all_summaries_ready
    Clipping.unsent.find_each { |clipping| clipping.update!(summary_status: :failed) }

    assert_no_difference -> { Newsletter.count } do
      assert_no_enqueued_emails { SendNewsletterJob.perform_now }
    end
  end

  private

  def make_all_summaries_ready
    clipping = clippings(:pending)
    clipping.source_variant.update!(locale: "pt-BR", summary: "Como o Solid Queue agenda jobs.")
    clipping.update!(summary_status: :summarized)
  end
end
