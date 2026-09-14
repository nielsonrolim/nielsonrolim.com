# Public (no auth) one-click unsubscribe endpoint referenced by the
# List-Unsubscribe headers on every newsletter email.
class UnsubscribesController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :destroy

  def show
    @subscriber = find_subscriber

    # A blank or already-used token means there is nothing left to unsubscribe,
    # so render the confirmation page as an "already gone" state instead of 404.
    render :gone and return if @subscriber.nil?
  end

  # POST powers RFC 8058 one-click unsubscribe from mail clients, which cannot
  # send a DELETE.
  def destroy
    subscriber = find_subscriber
    subscriber&.destroy

    redirect_to home_path(locale: I18n.default_locale),
                notice: t("unsubscribes.destroy.success"),
                status: :see_other
  end

  private

  def find_subscriber
    Subscriber.find_by_unsubscribe_token(params[:token])
  end
end
