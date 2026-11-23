module Admin
  # How to get the add-in into people's Office apps.
  class DeployController < BaseController
    def show
      @manifest_url = addin_manifest_url
      @https = request.ssl? || Capture::Addin.base_url(request).start_with?("https://")
    end
  end
end
