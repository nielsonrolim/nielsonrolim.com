# Public (no auth) subscription preferences, reached from the link every
# newsletter email carries. The token is the same capability the unsubscribe
# link uses, and the page is rendered in the subscriber's own language.
class PreferencesController < ApplicationController
  def show
    @subscriber = find_subscriber
    return render :gone if @subscriber.nil?

    I18n.with_locale(@subscriber.language) { render :show }
  end

  def update
    subscriber = find_subscriber
    return render :gone if subscriber.nil?

    # Captured before assigning, since the submitted value may be one the site
    # does not speak and must not be handed to I18n.
    current_language = subscriber.language
    subscriber.language = preference_params[:language]

    if subscriber.save
      I18n.with_locale(subscriber.language) do
        redirect_to preferences_path(token: subscriber.unsubscribe_token),
                    notice: t("preferences.update.success", language: subscriber.language)
      end
    else
      I18n.with_locale(current_language) do
        redirect_to preferences_path(token: subscriber.unsubscribe_token),
                    alert: t("preferences.update.invalid",
                             error: subscriber.errors.full_messages.to_sentence)
      end
    end
  end

  private

  def find_subscriber
    Subscriber.find_by_unsubscribe_token(params[:token])
  end

  def preference_params
    params.require(:subscriber).permit(:language)
  end
end
