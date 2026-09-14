module Reader
  class NewslettersController < BaseController
    def index
      @newsletters = Newsletter.newest_first
      @queued_count = Clipping.unsent.count
      @subscriber_count = Subscriber.count
    end

    def show
      @newsletter = Newsletter.find(params[:id])
    end

    # Manual trigger for the weekly issue, outside the recurring schedule.
    def create
      SendNewsletterJob.perform_later

      redirect_to reader_newsletters_path, notice: t("reader.newsletters.create.queued"), status: :see_other
    end
  end
end
