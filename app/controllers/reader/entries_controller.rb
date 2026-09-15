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
    #
    # Turbo Streams replace just the entry's action and append a toast, so the
    # list is not reloaded. Plain HTML requests keep the redirect fallback.
    def clip
      entry = Entry.find(params[:id])

      clipping = Clipping.new(entry: entry, title: entry.title, url: entry.url)

      if clipping.save
        @entry = entry
        respond_to do |format|
          format.turbo_stream
          format.html do
            redirect_back fallback_location: reader_entries_path,
                          notice: t("reader.entries.clip_success", title: clipping.title),
                          status: :see_other
          end
        end
      else
        message = clipping.errors.full_messages.to_sentence
        respond_to do |format|
          format.turbo_stream do
            render turbo_stream: turbo_stream.append(
              "toasts",
              partial: "layouts/toast",
              locals: { type: :alert, message: t("reader.entries.clip_failure", error: message) }
            )
          end
          format.html do
            redirect_back fallback_location: reader_entries_path,
                          alert: t("reader.entries.clip_failure", error: message),
                          status: :see_other
          end
        end
      end
    end

    # Removes the entry from the next issue: its unsent clipping is deleted, so
    # the entry can be clipped again. Mirrors #clip, in place over Turbo Streams.
    def unclip
      entry = Entry.find(params[:id])
      entry.clippings.unsent.destroy_all
      entry.association(:clippings).reset
      @entry = entry

      respond_to do |format|
        format.turbo_stream
        format.html do
          redirect_back fallback_location: reader_entries_path,
                        notice: t("reader.entries.unclip_success", title: entry.title),
                        status: :see_other
        end
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
