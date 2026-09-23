class SubscribersController < ApplicationController
  def create
    @subscriber = Subscriber.new(subscriber_params)
    # The language comes from the URL (see switch_locale), not from the form, so
    # what the visitor was reading is what gets recorded.
    @subscriber.language = I18n.locale.to_s

    # Honeypot: a filled-in hidden field means a bot, so pretend it worked.
    if @subscriber.nickname.present?
      redirect_to after_signup_path, notice: t("subscribers.create.success"), status: :see_other
      return
    end

    # Signing up again is not an error: the visitor gets the same confirmation as
    # a fresh signup, which also avoids revealing who is already on the list. Only
    # a genuinely unusable address is reported.
    if already_subscribed?(@subscriber.email) || @subscriber.save
      redirect_to after_signup_path, notice: t("subscribers.create.success"), status: :see_other
    else
      redirect_to after_signup_path, alert: t("subscribers.create.invalid"), status: :see_other
    end
  end

  private

  # The home page and the standalone newsletter page share this endpoint. A
  # submission carrying `from=newsletter` goes back to that page, so the visitor
  # sees the confirmation where they signed up; anything else returns home. Both
  # destinations are fixed internal paths, so the marker cannot redirect away.
  def after_signup_path
    params[:from] == "newsletter" ? newsletter_path : home_path
  end

  def already_subscribed?(email)
    email.present? && Subscriber.with_email(email).exists?
  end

  def subscriber_params
    params.require(:subscriber).permit(:email, :nickname)
  end
end
