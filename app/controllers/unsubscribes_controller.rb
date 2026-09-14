# Public (no auth) one-click unsubscribe endpoint referenced by the
# List-Unsubscribe headers on every newsletter email.
class UnsubscribesController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :destroy

  def show
    @subscriber = find_subscriber

    # A blank or already-used token means there is nothing left to unsubscribe,
    # so render the confirmation page as an "already gone" state instead of 404.
    return render :gone if @subscriber.nil?

    # The page follows the language the subscriber reads the newsletter in.
    I18n.with_locale(@subscriber.language) { render :show }
  end

  # POST powers RFC 8058 one-click unsubscribe from mail clients, which cannot
  # send a DELETE.
  def destroy
    subscriber = find_subscriber

    # Read before deleting: the confirmation and the page they land on follow the
    # language they were reading the newsletter in.
    language = subscriber&.language || I18n.default_locale.to_s
    subscriber&.destroy

    I18n.with_locale(language) do
      redirect_to home_path(locale: language),
                  notice: t("unsubscribes.destroy.success"),
                  status: :see_other
    end
  end

  private

  def find_subscriber
    Subscriber.find_by_unsubscribe_token(params[:token])
  end
end
