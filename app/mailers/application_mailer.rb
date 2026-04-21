class ApplicationMailer < ActionMailer::Base
  default from: Branding.mailer_sender
  layout "mailer"
end
