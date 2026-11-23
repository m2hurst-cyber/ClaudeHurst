# Office on the web hosts add-in pages in an iframe on Microsoft domains, so these
# pages drop Rails' default X-Frame-Options and allow only Office as a framer.
module OfficeFraming
  extend ActiveSupport::Concern

  OFFICE_FRAME_ANCESTORS = %w[
    'self' https://*.office.com https://*.office365.com https://*.officeapps.live.com
    https://*.sharepoint.com https://*.microsoft365.com https://*.cloud.microsoft https://*.live.com
  ].freeze

  included do
    after_action :allow_office_framing
  end

  private

  def allow_office_framing
    response.headers.delete("X-Frame-Options")
    response.headers["Content-Security-Policy"] = "frame-ancestors #{OFFICE_FRAME_ANCESTORS.join(' ')}"
  end
end
