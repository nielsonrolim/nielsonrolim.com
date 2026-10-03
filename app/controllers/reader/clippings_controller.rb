module Reader
  class ClippingsController < BaseController
    # The queue for the next issue: everything marked but not yet sent, failed
    # ones included so they are visible and fixable.
    def index
      @clippings = Clipping.unsent.includes(:variants, entry: :feed).order(:created_at)
      @recent_newsletters = Newsletter.newest_first.limit(5)
      @shippable_count = Clipping.shippable.count
      @clipping = Clipping.new
    end

    # Adds a clipping by hand from a URL: the page is fetched for its title and
    # body in the background (FetchSourceTextJob), so a slow fetch — a YouTube
    # transcript can take minutes — does not hold the request open. The clipping
    # is created immediately with the typed title (or the host) and the reader
    # sees the "fetching" state until the text is stored.
    def create
      url = create_params[:url].to_s.strip

      if duplicate_url?(url)
        redirect_to reader_clippings_path, alert: t("reader.clippings.create.duplicate"), status: :see_other
        return
      end

      # The source (site domain or YouTube channel) is resolved before the
      # fetch so it is stored even when the page itself cannot be fetched.
      @clipping = Clipping.new(source_name: SourceNameResolver.new.call(url))
      # The language is not known yet, so the source edition starts without one.
      # Its title is what the reader typed, or the host until the fetch finds
      # the real one.
      title = create_params[:title].to_s.strip.presence
      variant = @clipping.variants.build(url: url, origin: :generated, title: title || host_of(url))

      if @clipping.save
        redirect_after_create(@clipping)
      else
        redirect_to reader_clippings_path,
                    alert: t("reader.clippings.create.invalid", error: @clipping.errors.full_messages.to_sentence),
                    status: :see_other
      end
    end

    def edit
      @clipping = Clipping.find(params[:id])
    end

    # Edits the story by hand: each language has its own URL, title and summary,
    # so a story published in more than one language can point each reader at the
    # right edition. What is saved here is marked manual and is not overwritten
    # by a later summary run. The article's own language is not edited here: the
    # detection from the summary run decides which edition is the source.
    def update
      @clipping = Clipping.find(params[:id])
      @clipping.source_text = update_params[:source_text] if update_params.key?(:source_text)
      assign_variants(@clipping)

      if @clipping.save
        redirect_to reader_clippings_path,
                    notice: t("reader.clippings.update.success", title: @clipping.display_title),
                    status: :see_other
      else
        flash.now[:alert] = t("reader.clippings.update.invalid",
                              error: @clipping.errors.full_messages.to_sentence)
        render :edit, status: :unprocessable_content
      end
    end

    # Runs the summary and the translation for a clipping, on demand. Also how a
    # clipping added without a source gets one, once its text has been pasted in.
    # When the text has not been stored yet (a manual clipping still fetching, or
    # one whose fetch failed), fetch it first and let that job chain the summary;
    # otherwise run the summary directly.
    # This is an explicit request, so it overwrites a summary edited by hand; an
    # automatic run leaves those alone (see Clipping#apply_summary).
    def generate_summary
      clipping = Clipping.find(params[:id])

      if clipping.source_text.blank? && clipping.primary_variant&.url.present?
        clipping.update!(summary_status: :pending, summary_error: nil)
        FetchSourceTextJob.perform_later(clipping.id, force: true)
      else
        clipping.update!(summary_status: :pending, summary_error: nil)
        GenerateSummaryJob.perform_later(clipping.id, 1, true)
      end

      redirect_back fallback_location: reader_clippings_path,
                    notice: t("reader.clippings.generate_summary.queued", title: clipping.display_title),
                    status: :see_other
    end

    # Re-fetches the article and replaces the stored text, in the background, so
    # a page whose extraction was fixed (or that came in incomplete) can be
    # summarized again without deleting the clipping. Text pasted by hand is only
    # replaced when this is asked for on purpose. This does not run the summary:
    # the text is refreshed, and the reader regenerates on demand.
    def refetch_source
      clipping = Clipping.find(params[:id])
      url = clipping.primary_variant&.url

      if url.blank?
        redirect_back fallback_location: edit_reader_clipping_path(clipping),
                      alert: t("reader.clippings.refetch_source.no_url"),
                      status: :see_other
        return
      end

      clipping.update!(summary_status: :fetching)
      FetchSourceTextJob.perform_later(clipping.id, force: true)

      redirect_back fallback_location: edit_reader_clipping_path(clipping),
                    notice: t("reader.clippings.refetch_source.queued", title: clipping.display_title),
                    status: :see_other
    end

    def destroy
      clipping = Clipping.find(params[:id])
      title = clipping.display_title
      clipping.destroy

      redirect_to reader_clippings_path,
                  notice: t("reader.clippings.destroy.success", title: title),
                  status: :see_other
    end

    private

    def duplicate_url?(url)
      return false if url.blank?

      Clipping.unsent.joins(:variants).where("lower(clipping_variants.url) = ?", url.downcase).exists?
    end

    # A clipping added by hand is created straight away; its text is fetched in
    # the background (FetchSourceTextJob), so this always lands on the queue with
    # the "fetching" state showing.
    def redirect_after_create(clipping)
      redirect_to reader_clippings_path,
                  notice: t("reader.clippings.create.success", title: clipping.display_title),
                  status: :see_other
    end

    # Maps the per-language form fields onto variants. A locale with nothing
    # typed is removed; one with any content is written as a manual edition. The
    # language-less source edition keeps its placeholder until the summary run
    # detects the article's language.
    def assign_variants(clipping)
      Clipping::LANGUAGES.each do |locale|
        key = SupportedLanguages.param_key(locale)
        fields = [ :"url_#{key}", :"title_#{key}", :"summary_#{key}" ]
        next if fields.none? { |field| update_params.key?(field) }

        variant = clipping.stored_variant(locale)
        title = update_params[:"title_#{key}"].to_s.strip
        url = update_params[:"url_#{key}"].to_s.strip
        summary = update_params[:"summary_#{key}"].to_s

        if title.blank? && url.blank? && summary.blank?
          variant&.mark_for_destruction
          next
        end

        variant ||= clipping.variants.build
        variant.locale = locale unless variant.equal?(clipping.source_variant)
        variant.origin = :manual
        variant.title = title.presence || variant.title.presence || clipping.display_title
        # Blank means "no published edition in this language": the URL is left
        # empty on purpose, and readers fall back to the edition that exists.
        variant.url = url.presence
        variant.summary = summary.presence
      end
    end

    def host_of(url)
      URI.parse(url).host.to_s
    rescue URI::InvalidURIError
      ""
    end

    def create_params
      @create_params ||= params.require(:clipping).permit(:url, :title)
    end

    def update_params
      @update_params ||= params.require(:clipping).permit(
        :source_text,
        :url_pt_br, :title_pt_br, :summary_pt_br,
        :url_en_us, :title_en_us, :summary_en_us
      )
    end
  end
end
