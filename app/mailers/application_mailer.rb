class ApplicationMailer < ActionMailer::Base
  layout "mailer"

  default from: -> { ENV.fetch("NEWSLETTER_FROM", "Nielson Rolim <newsletter@nielsonrolim.com>") }
end
