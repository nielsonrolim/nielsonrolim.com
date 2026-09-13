class SubscribersController < ApplicationController
  def create
    @subscriber = Subscriber.new(subscriber_params)

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
