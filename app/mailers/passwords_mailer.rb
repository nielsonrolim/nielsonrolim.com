class PasswordsMailer < ApplicationMailer
  def reset(user)
    @user = user
    mail subject: t("auth.passwords.mailer.subject"), to: user.email_address
  end
end
