module Reader
  class ClippingsController < BaseController
    # The queue for the next issue: everything marked but not yet sent.
    def index
      @clippings = Clipping.unsent.includes(entry: :feed).order(:created_at)
      @recent_newsletters = Newsletter.newest_first.limit(5)
    end

    def destroy
      clipping = Clipping.find(params[:id])
      title = clipping.title
      clipping.destroy

      redirect_to reader_clippings_path,
                  notice: t("reader.clippings.destroy.success", title: title),
                  status: :see_other
    end

    # Re-runs the summary for a clipping whose generation failed.
    def retry_summary
      clipping = Clipping.find(params[:id])
      clipping.update!(summary_status: :pending, summary_error: nil)
      GenerateSummaryJob.perform_later(clipping.id)

      redirect_to reader_clippings_path,
                  notice: t("reader.clippings.retry_summary.queued", title: clipping.title),
                  status: :see_other
    end
  end
end
