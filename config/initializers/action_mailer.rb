# Action Mailer settings for the weekly clipping newsletter.
#
# Delivery method per environment:
#   test        -> :test (captured by ActionMailer::TestHelper)
#   development -> :letter_opener, which renders the email under
#                    tmp/letter_opener and opens it in a browser. A local run
#                    can therefore never email real subscribers.
#   production  -> :smtp when SMTP_ADDRESS is set, otherwise :file plus a boot
#                    warning, so a misconfigured box never silently loses an issue.
#
# MAIL_DELIVERY overrides the choice explicitly (smtp | file | letter_opener).
Rails.application.configure do
  host = ENV.fetch("APP_HOST", "localhost:3000")
  protocol = ENV.fetch("APP_PROTOCOL", host.start_with?("localhost") ? "http" : "https")

  config.action_mailer.default_url_options = { host: host, protocol: protocol }
  config.action_mailer.perform_deliveries = true

  smtp_address = ENV["SMTP_ADDRESS"].presence
  override = ENV["MAIL_DELIVERY"].presence&.downcase

  # letter_opener is a development-group gem, so it must never be selected
  # elsewhere: the delivery method would not be registered and every send raises.
  letter_opener_available = Rails.env.development? && defined?(LetterOpener)

  delivery_method =
    if Rails.env.test? then :test
    elsif override == "smtp" && smtp_address then :smtp
    elsif override == "file" then :file
    elsif override == "letter_opener" && letter_opener_available then :letter_opener
    elsif override.present? then nil # invalid or unusable override, resolved below
    elsif Rails.env.development? && letter_opener_available then :letter_opener
    elsif smtp_address then :smtp
    else :file
    end

  if delivery_method.nil?
    delivery_method = smtp_address ? :smtp : :file
    Rails.logger.warn(
      "[action_mailer] MAIL_DELIVERY=#{override.inspect} cannot be used in #{Rails.env} " \
      "(letter_opener is development-only, smtp needs SMTP_ADDRESS); falling back to #{delivery_method}."
    )
  end

  config.action_mailer.delivery_method = delivery_method

  case delivery_method
  when :smtp
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.smtp_settings = {
      address: smtp_address,
      port: Integer(ENV.fetch("SMTP_PORT", 587)),
      domain: ENV["SMTP_DOMAIN"].presence,
      user_name: ENV["SMTP_USERNAME"].presence,
      password: ENV["SMTP_PASSWORD"].presence,
      authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain").to_sym,
      enable_starttls_auto: true
    }.compact
  when :letter_opener
    # Launchy needs a browser; on a headless box that fails, and it must not
    # take the send job down with it — the rendered email is already on disk.
    # Rendered mail goes to LetterOpener.configuration.location
    # (tmp/letter_opener by default); configuring it here would run before the
    # letter_opener railtie registers the delivery method.
    config.action_mailer.raise_delivery_errors = false

    Rails.logger.info(
      "[action_mailer] delivering to tmp/letter_opener and opening a browser tab per email."
    )
  when :file
    config.action_mailer.file_settings = { location: Rails.root.join("tmp/mails") }
    config.action_mailer.raise_delivery_errors = false

    reason = smtp_address ? "SMTP delivery is not enabled here" : "SMTP_ADDRESS is not set"
    Rails.logger.warn(
      "[action_mailer] emails are written to tmp/mails instead of being sent (#{reason}). " \
      "Set MAIL_DELIVERY=smtp to deliver for real."
    )
  end
end
