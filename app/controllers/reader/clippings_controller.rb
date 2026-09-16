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
    # body. When the fetch fails the clipping is still created — marked failed
    # with the reason — so the article text can be pasted on the edit page and
    # the summary generated from there.
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
      variant = @clipping.variants.build(url: url, origin: :generated)
      fetch_article(@clipping, variant, url, provided_title: create_params[:title].to_s.strip.presence)

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
    # by a later summary run.
    def update
      @clipping = Clipping.find(params[:id])
      @clipping.language = update_params[:language] if update_params.key?(:language)
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
    def generate_summary
      clipping = Clipping.find(params[:id])
      clipping.update!(summary_status: :pending, summary_error: nil)
      GenerateSummaryJob.perform_later(clipping.id)

      redirect_back fallback_location: reader_clippings_path,
                    notice: t("reader.clippings.generate_summary.queued", title: clipping.display_title),
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

    def fetch_article(clipping, variant, url, provided_title:)
      article = ArticleFetcher.new.call(url)

      variant.title = provided_title || article.title
      clipping.source_text = article.text
    rescue ArticleFetcher::Error => e
      variant.title = provided_title || host_of(url)
      clipping.summary_status = :failed
      clipping.summary_error = t("reader.clippings.create.fetch_failed", error: e.message)
    end

    def redirect_after_create(clipping)
      if clipping.failed?
        redirect_to edit_reader_clipping_path(clipping),
                    alert: t("reader.clippings.create.added_without_source"),
                    status: :see_other
      else
        redirect_to reader_clippings_path,
                    notice: t("reader.clippings.create.success", title: clipping.display_title),
                    status: :see_other
      end
    end

    # Maps the per-language form fields onto variants. A locale with nothing
    # typed is removed; one with any content is written as a manual edition. The
    # language-less source edition adopts the language chosen for it.
    def assign_variants(clipping)
      chosen = update_params[:language].presence
      if chosen && (source = clipping.source_variant)
        source.locale = chosen
      end

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
        keep_sourceless = variant.locale.blank? && chosen.blank?
        variant.locale = locale unless keep_sourceless
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
        :language, :source_text,
        :url_pt_br, :title_pt_br, :summary_pt_br,
        :url_en_us, :title_en_us, :summary_en_us
      )
    end
  end
end
