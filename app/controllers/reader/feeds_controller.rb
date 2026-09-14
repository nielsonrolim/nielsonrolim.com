module Reader
  class FeedsController < BaseController
    def index
      @feeds = Feed.alphabetical
      @entry_counts = Entry.group(:feed_id).count
      @feed = Feed.new
    end

    # Adds a feed from a bare URL: it is fetched once to learn the title and
    # site link the feed advertises, then queued for a full import.
    def create
      url = feed_params[:url].to_s.strip

      if Feed.where(url: url).exists?
        redirect_to reader_feeds_path, alert: t("reader.feeds.create.duplicate")
        return
      end

      feed = FeedFetcher.create_from_url(url, category: feed_params[:category].presence)
      RefreshFeedsJob.perform_later

      redirect_to reader_feeds_path, notice: t("reader.feeds.create.success", title: feed.title)
    rescue FeedFetcher::Error, Feedjira::NoParserAvailable,
           ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      redirect_to reader_feeds_path, alert: t("reader.feeds.create.invalid", error: e.message)
    end

    def destroy
      feed = Feed.find(params[:id])
      title = feed.title
      feed.destroy

      redirect_to reader_feeds_path, notice: t("reader.feeds.destroy.success", title: title), status: :see_other
    end

    def refresh
      feed = Feed.find(params[:id])
      result = FeedFetcher.new(feed).call

      if result.success?
        redirect_to reader_feeds_path,
                    notice: t("reader.feeds.refresh.success", title: feed.title, count: result.new_entries),
                    status: :see_other
      else
        redirect_to reader_feeds_path,
                    alert: t("reader.feeds.refresh.failure", title: feed.title, error: result.error),
                    status: :see_other
      end
    end

    def refresh_all
      RefreshFeedsJob.perform_later

      redirect_to reader_feeds_path, notice: t("reader.feeds.refresh_all.queued"), status: :see_other
    end

    private

    def feed_params
      params.require(:feed).permit(:url, :category)
    end
  end
end
