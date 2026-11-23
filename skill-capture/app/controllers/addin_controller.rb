# Public pages that make up the Office add-in: manifest, task pane and help.
# The task pane authenticates to the API with a per-person token (see AddinConnectController).
class AddinController < ActionController::Base
  include OfficeFraming

  layout "addin"
  protect_from_forgery with: :exception

  def taskpane
    @capture_enabled = Capture::Config.enabled?
  end

  def support; end

  # The add-in-only XML manifest, generated for this server's URL. Office requires HTTPS
  # (localhost with a trusted dev certificate is fine for sideloading).
  def manifest
    @base = Capture::Addin.base_url(request)
    @addin_id = Capture::Addin.id
    render formats: :xml, layout: false
  end
end
