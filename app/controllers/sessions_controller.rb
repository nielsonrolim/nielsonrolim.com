class SessionsController < Auth::BaseController
  rate_limit to: 10, within: 3.minutes, only: :create,
    with: -> { redirect_to new_session_path, alert: t("auth.sessions.rate_limited") }

  def new
  end

  def create
    if user = User.authenticate_by(params.permit(:email_address, :password))
      start_new_session_for user
      redirect_to after_authentication_url
    else
      redirect_to new_session_path, alert: t("auth.sessions.invalid_credentials")
    end
  end

  def destroy
    terminate_session
    redirect_to new_session_path, status: :see_other, notice: t("auth.sessions.signed_out")
  end

  private

  # The login exists only for /admin, so land there (not on the public home) when
  # there is no stored return path from an intercepted request.
  def after_authentication_url
    session.delete(:return_to_after_authenticating) || admin_root_path
  end
end
