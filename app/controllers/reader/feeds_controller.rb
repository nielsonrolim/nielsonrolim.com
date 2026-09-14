module Reader
  class FeedsController < BaseController
    def index
      @categories = Category.alphabetical
      @category = Category.find_by(id: params[:category_id])
      # Feeds that carry no category at all are worth surfacing on this page.
      @uncategorised = params[:uncategorised].present?

      @feeds = filtered_feeds
      @entry_counts = Entry.group(:feed_id).count
      @feed = Feed.new
    end

    # Adds a feed from a bare URL: it is fetched once to learn the title and
    # site link the feed advertises, then queued for a full import. The single
    # optional category name is kept as a compact one-field form; categories are
    # refined on the edit page.
    def create
      url = create_params[:url].to_s.strip

      if Feed.where(url: url).exists?
        redirect_to reader_feeds_path, alert: t("reader.feeds.create.duplicate")
        return
      end

      feed = FeedFetcher.create_from_url(url, category: create_params[:category].presence)
      RefreshFeedsJob.perform_later

      redirect_to reader_feeds_path, notice: t("reader.feeds.create.success", title: feed.display_title)
    rescue FeedFetcher::Error, Feedjira::NoParserAvailable,
           ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      redirect_to reader_feeds_path, alert: t("reader.feeds.create.invalid", error: e.message)
    end

    def edit
      @feed = Feed.find(params[:id])
      @categories = Category.alphabetical
    end

    # Edits only what the reader owns: the display title override and the
    # categories. The URL stays put because entries are matched by it.
    def update
      @feed = Feed.find(params[:id])
      @categories = Category.alphabetical
      @feed.custom_title = update_params[:custom_title]

      @feed.transaction do
        @feed.category_ids = resolved_category_ids
        @feed.save!
      end

      redirect_to reader_feeds_path,
                  notice: t("reader.feeds.update.success", title: @feed.display_title),
                  status: :see_other
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = t("reader.feeds.update.invalid",
                            error: e.record.errors.full_messages.to_sentence)
      render :edit, status: :unprocessable_content
    end

    def destroy
      feed = Feed.find(params[:id])
      title = feed.display_title
      feed.destroy

      redirect_to reader_feeds_path, notice: t("reader.feeds.destroy.success", title: title), status: :see_other
    end

    def refresh
      feed = Feed.find(params[:id])
      result = FeedFetcher.new(feed).call

      if result.success?
        redirect_to reader_feeds_path,
                    notice: t("reader.feeds.refresh.success", title: feed.display_title, count: result.new_entries),
                    status: :see_other
      else
        redirect_to reader_feeds_path,
                    alert: t("reader.feeds.refresh.failure", title: feed.display_title, error: result.error),
                    status: :see_other
      end
    end

    def refresh_all
      RefreshFeedsJob.perform_later

      redirect_to reader_feeds_path, notice: t("reader.feeds.refresh_all.queued"), status: :see_other
    end

    private

    # Feeds for the current filter. An unknown category id falls back to the
    # full list rather than erroring, same as the entry filters.
    def filtered_feeds
      scope = Feed.alphabetical.includes(:categories)

      if @category
        scope.joins(:categories).where(categories: { id: @category.id })
      elsif @uncategorised
        scope.where.missing(:categories)
      else
        scope
      end
    end

    def create_params
      params.require(:feed).permit(:url, :category)
    end

    def update_params
      params.require(:feed).permit(:custom_title, category_ids: [])
    end

    # The checkboxes give ids; the free-text field gives names for categories
    # that do not exist yet. Assigning the whole set at once also handles
    # removals, which is why the two are merged before assignment. Unknown ids
    # are dropped rather than raising, so a stale form cannot 500.
    def resolved_category_ids
      requested = Array(update_params[:category_ids]).reject(&:blank?).map(&:to_i)
      checked = Category.where(id: requested).pluck(:id)
      created = new_category_names.filter_map { |name| Category.find_or_create_by_name(name)&.id }

      (checked + created).uniq
    end

    def new_category_names
      params.dig(:feed, :new_categories).to_s.split(",").map(&:strip).reject(&:blank?)
    end
  end
end
