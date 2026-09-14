module Admin
  # Landing page for the authenticated area: a few counts plus links into the
  # sections that live underneath it.
  class DashboardController < BaseController
    def index
      @feed_count = Feed.count
      @entry_count = Entry.count
      @queued_clippings = Clipping.shippable.count
      @subscriber_count = Subscriber.count
      @latest_newsletter = Newsletter.newest_first.first
      @failed_jobs = SolidQueue::FailedExecution.count
    end
  end
end
