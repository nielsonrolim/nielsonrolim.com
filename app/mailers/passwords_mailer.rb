class PasswordsMailer < ApplicationMailer
  # Transactional mail must not leave from the newsletter sender: a dedicated
  # no-reply address protects the newsletter's sending reputation and the brand.
  # Overrides ApplicationMailer's `from` for this mailer only.
  default from: -> { ENV.fetch("PASSWORDS_FROM", "Nielson Rolim <nao-responda@nielsonrolim.com>") }

  def reset(user)
    @user = user
    mail subject: t("auth.passwords.mailer.subject"), to: user.email_address
  end
end
