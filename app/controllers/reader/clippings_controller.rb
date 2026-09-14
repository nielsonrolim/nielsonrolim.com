module Reader
  class ClippingsController < BaseController
    # The queue for the next issue: everything marked but not yet sent, failed
    # ones included so they are visible and fixable.
    def index
      @clippings = Clipping.unsent.includes(entry: :feed).order(:created_at)
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

      if Clipping.unsent.where("lower(url) = ?", url.downcase).exists?
        redirect_to reader_clippings_path, alert: t("reader.clippings.create.duplicate")
        return
      end

      # The source (site domain or YouTube channel) is resolved before the
      # fetch so it is stored even when the page itself cannot be fetched.
      @clipping = Clipping.new(url: url, source_name: SourceNameResolver.new.call(url))
      fetch_article(@clipping, url, provided_title: create_params[:title].to_s.strip.presence)

      if @clipping.save
        redirect_after_create(@clipping)
      else
        redirect_to reader_clippings_path,
                    alert: t("reader.clippings.create.invalid", error: @clipping.errors.full_messages.to_sentence)
      end
    end

    def edit
      @clipping = Clipping.find(params[:id])
    end

    # Edits every field by hand, including the content per language, so a
    # mis-detected language or a bad translation can be corrected without
    # regenerating.
    def update
      @clipping = Clipping.find(params[:id])
      @clipping.assign_attributes(
        url: update_params[:url],
        language: update_params[:language],
        source_text: update_params[:source_text]
      )
      assign_localized_content(@clipping)

      if @clipping.save
        redirect_to reader_clippings_path,
                    notice: t("reader.clippings.update.success", title: @clipping.title),
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
                    notice: t("reader.clippings.generate_summary.queued", title: clipping.title),
                    status: :see_other
    end

    def destroy
      clipping = Clipping.find(params[:id])
      title = clipping.title
      clipping.destroy

      redirect_to reader_clippings_path,
                  notice: t("reader.clippings.destroy.success", title: title),
                  status: :see_other
    end

    private

    def fetch_article(clipping, url, provided_title:)
      article = ArticleFetcher.new.call(url)

      clipping.title = provided_title || article.title
      clipping.source_text = article.text
    rescue ArticleFetcher::Error => e
      clipping.title = provided_title || host_of(url)
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
                    notice: t("reader.clippings.create.success", title: clipping.title),
                    status: :see_other
      end
    end

    # The form edits content per language; which column each one belongs in is
    # decided by the clipping's language (the original lives in `title`/`summary`).
    # Only keys the request actually carried are assigned, so a partial update
    # cannot blank a column by omission — while an explicitly emptied field still
    # clears it.
    def assign_localized_content(clipping)
      source = clipping.language.presence || Clipping::LANGUAGES.first
      translated = SupportedLanguages.other(source)

      [
        [ :title, source, :title ],
        [ :summary, source, :summary ],
        [ :title_translated, translated, :title ],
        [ :summary_translated, translated, :summary ]
      ].each do |column, locale, field|
        param = :"#{field}_#{SupportedLanguages.param_key(locale)}"
        clipping.public_send(:"#{column}=", update_params[param]) if update_params.key?(param)
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
        :url, :language, :source_text,
        :title_pt_br, :summary_pt_br, :title_en_us, :summary_en_us
      )
    end
  end
end
