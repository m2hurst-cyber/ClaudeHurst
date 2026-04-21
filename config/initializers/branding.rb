Rails.application.config.x.branding = ActiveSupport::OrderedOptions.new
Rails.application.config.x.branding.company_name = "Great Southern Beverages"
Rails.application.config.x.branding.tagline = "Co-pack CRM · ERP"
Rails.application.config.x.branding.mailer_sender = "noreply@greatsouthernbeverages.local"

module Branding
  module_function

  def company_name
    Rails.configuration.x.branding.company_name
  end

  def tagline
    Rails.configuration.x.branding.tagline
  end

  def mailer_sender
    Rails.configuration.x.branding.mailer_sender
  end
end