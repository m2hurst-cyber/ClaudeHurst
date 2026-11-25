module Capture
  # Whether this installation can actually send a person an email, and what is missing
  # if it cannot. Shown to admins rather than discovered by a locked-out colleague.
  module MailCheck
    REQUIRED = { "SMTP_ADDRESS" => "the mail server", "SMTP_USER_NAME" => "the username",
                 "SMTP_PASSWORD" => "the password", "MAIL_FROM" => "the address mail comes from" }.freeze

    module_function

    def missing = REQUIRED.reject { |key, _| ENV[key].present? }
    def configured? = missing.empty?
    def summary
      return "Mail is configured: resets are sent from #{ENV['MAIL_FROM']} via #{ENV['SMTP_ADDRESS']}." if configured?
      "Mail is not configured, so a password reset cannot reach anyone. Missing #{missing.values.to_sentence} " \
        "(#{missing.keys.join(', ')})."
    end
  end
end
