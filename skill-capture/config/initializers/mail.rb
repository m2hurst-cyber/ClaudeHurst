# Mail, from the environment.
#
# Nothing in the product emails anyone during normal use — notifications live in the
# console. The one thing that does is a password reset, and a reset that is silently
# never delivered is worse than one that fails loudly: the person waits, then asks an
# admin, who finds nothing wrong because nothing errored.
#
# So: configured from env, and when it is not configured we say so at boot and refuse to
# pretend. Set SMTP_ADDRESS, SMTP_USER_NAME, SMTP_PASSWORD and MAIL_FROM.
Rails.application.configure do
  from = ENV["MAIL_FROM"].presence
  host = ENV["SKILL_CAPTURE_PUBLIC_URL"].presence&.then { |u| URI(u).host rescue nil }

  config.action_mailer.default_options = { from: from } if from
  config.action_mailer.default_url_options = { host: host, protocol: "https" } if host

  if ENV["SMTP_ADDRESS"].present?
    config.action_mailer.delivery_method = :smtp
    config.action_mailer.perform_deliveries = true
    config.action_mailer.raise_delivery_errors = true
    config.action_mailer.smtp_settings = {
      address: ENV["SMTP_ADDRESS"],
      port: ENV.fetch("SMTP_PORT", 587).to_i,
      domain: ENV["SMTP_DOMAIN"].presence || host,
      user_name: ENV["SMTP_USER_NAME"],
      password: ENV["SMTP_PASSWORD"],
      authentication: ENV.fetch("SMTP_AUTHENTICATION", "plain").to_sym,
      enable_starttls_auto: ENV.fetch("SMTP_STARTTLS", "true") == "true",
      open_timeout: 10, read_timeout: 20
    }.compact
  elsif Rails.env.production?
    # Loud, once, at boot — rather than quiet, every time someone forgets their password.
    config.after_initialize do
      Rails.logger.warn("MAIL IS NOT CONFIGURED: password resets cannot be delivered. " \
                        "Set SMTP_ADDRESS, SMTP_USER_NAME, SMTP_PASSWORD and MAIL_FROM.")
    end
  end
end
