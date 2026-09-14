class SubscribersController < ApplicationController
  def create
    @subscriber = Subscriber.new(subscriber_params)
    # The language comes from the URL (see switch_locale), not from the form, so
    # what the visitor was reading is what gets recorded.
    @subscriber.language = I18n.locale.to_s

    # Honeypot: a filled-in hidden field means a bot, so pretend it worked.
    if @subscriber.nickname.present?
      redirect_to home_path, notice: t("subscribers.create.success")
      return
    end

    if @subscriber.save
      redirect_to home_path, notice: t("subscribers.create.success")
    else
      redirect_to home_path, alert: t("subscribers.create.invalid")
    end
  end

  private

  def subscriber_params
    params.require(:subscriber).permit(:email, :nickname)
  end
end
