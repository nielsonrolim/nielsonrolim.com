module Reader
  class EntriesController < BaseController
    PER_PAGE = 50

    def index
      @feeds = Feed.alphabetical.includes(:categories)
      @categories = Category.alphabetical
      @feed = Feed.find_by(id: params[:feed_id])
      @category = Category.find_by(id: params[:category_id])

      scope = Entry.recent.includes(:feed, :clippings)
      scope = scope.where(feed_id: @feed.id) if @feed
      scope = scope.joins(feed: :categories).where(categories: { id: @category.id }) if @category
      scope = scope.since(since_cutoff) if since_cutoff

      @total = scope.count
      @entries = scope.offset(offset).limit(PER_PAGE).to_a
      @page = page
      @pages = (@total.to_f / PER_PAGE).ceil

      build_feed_groups
    end

    # Marks an entry for the next newsletter issue. Creating the clipping also
    # enqueues the AI summary (see Clipping#enqueue_summary_generation).
    def clip
      entry = Entry.find(params[:id])

      clipping = Clipping.new(entry: entry, title: entry.title, url: entry.url)

      if clipping.save
        redirect_back fallback_location: reader_entries_path,
                      notice: t("reader.entries.clip_success", title: clipping.title),
                      status: :see_other
      else
        message = clipping.errors.full_messages.to_sentence
        redirect_back fallback_location: reader_entries_path,
                      alert: t("reader.entries.clip_failure", error: message),
                      status: :see_other
      end
    end

    private

    # Feeds for the picker, grouped by category. A feed with several categories
    # shows up under each of them, and anything uncategorised goes last.
    def build_feed_groups
      @feed_groups = @categories.filter_map do |category|
        grouped = @feeds.select { |feed| feed.categories.any? { |own| own.id == category.id } }
        [ category, grouped ] if grouped.any?
      end

      uncategorised = @feeds.select { |feed| feed.categories.empty? }
      @feed_groups << [ nil, uncategorised ] if uncategorised.any?
    end

    def page
      [ params[:page].to_i, 1 ].max
    end

    def offset
      (page - 1) * PER_PAGE
    end

    def since_cutoff
      return nil if params[:since].blank?

      Integer(params[:since]).days.ago
    rescue ArgumentError, TypeError
      nil
    end
  end
end
