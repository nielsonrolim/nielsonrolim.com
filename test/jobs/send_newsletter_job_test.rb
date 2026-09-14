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

    def issue(newsletter:, subscriber:)
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

    assert_includes issue.body, "Rails 8.1 ships with a new queue UI"
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
    assert_nil issue.clippings.find(clippings(:pending).id).summary
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
      SendNewsletterJob.new(SendNewsletterJob::MAX_DEFERRALS).perform_now
    end
  end

  private

  def make_all_summaries_ready
    clippings(:pending).update!(summary_status: :summarized, summary: "Como o Solid Queue agenda jobs.")
  end
end
