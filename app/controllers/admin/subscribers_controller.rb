module Admin
  # Manages the newsletter list: who is subscribed, in which language, and
  # removal. Removal is a real delete (not a soft unsubscribe) because the
  # subscriber asked to be forgotten, so nothing about them is kept.
  class SubscribersController < BaseController
    PER_PAGE = 30

    def index
      @query = params[:q].to_s.strip
      @total = filtered.count
      @page = [ params[:page].to_i, 1 ].max
      @pages = [ (@total.to_f / PER_PAGE).ceil, 1 ].max
      @subscribers = filtered.newest_first.offset((@page - 1) * PER_PAGE).limit(PER_PAGE).to_a

      @recent_newsletters = Newsletter.sent.newest_first.limit(10)
      @subscriber = Subscriber.new
    end

    def create
      @subscriber = Subscriber.new(create_params)

      if @subscriber.save
        redirect_to index_path,
                    notice: t("admin.subscribers.create.success", email: @subscriber.email),
                    status: :see_other
      else
        redirect_to index_path,
                    alert: t("admin.subscribers.create.invalid",
                             error: @subscriber.errors.full_messages.to_sentence),
                    status: :see_other
      end
    end

    # Only the language is editable: it is what decides which rendering of an
    # issue the subscriber receives.
    def update
      subscriber = Subscriber.find(params[:id])
      subscriber.language = update_params[:language]

      if subscriber.save
        redirect_to index_path, notice: t("admin.subscribers.update.success", email: subscriber.email),
                    status: :see_other
      else
        redirect_to index_path,
                    alert: t("admin.subscribers.update.invalid",
                             error: subscriber.errors.full_messages.to_sentence),
                    status: :see_other
      end
    end

    def destroy
      subscriber = Subscriber.find(params[:id])
      email = subscriber.email
      subscriber.destroy

      redirect_to index_path, notice: t("admin.subscribers.destroy.success", email: email), status: :see_other
    end

    def bulk_destroy
      ids = Array(params[:subscriber_ids]).reject(&:blank?)
      removed = Subscriber.where(id: ids).destroy_all.size

      redirect_to index_path, notice: t("admin.subscribers.bulk_destroy.success", count: removed), status: :see_other
    end

    # Exports what the current search shows, not the whole table.
    def export
      send_data Subscriber.to_csv(filtered.newest_first),
                filename: "subscribers-#{Date.current}.csv",
                type: "text/csv"
    end

    def resend
      subscriber = Subscriber.find(params[:id])
      newsletter = Newsletter.sent.find(params[:newsletter_id])
      NewsletterMailer.issue(newsletter: newsletter, subscriber: subscriber).deliver_later

      redirect_to index_path, notice: t("admin.subscribers.resend.success", email: subscriber.email), status: :see_other
    end

    private

    def filtered
      Subscriber.search(params[:q])
    end

    # Keeps the current search and page when returning to the list.
    def index_path
      admin_subscribers_path(q: params[:q].presence, page: params[:page].presence)
    end

    def create_params
      params.require(:subscriber).permit(:email, :language)
    end

    def update_params
      params.require(:subscriber).permit(:language)
    end
  end
end
