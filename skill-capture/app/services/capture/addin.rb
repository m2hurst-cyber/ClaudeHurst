module Capture
  module Addin
    module_function

    # Stable add-in id (a GUID). Set SKILL_CAPTURE_ADDIN_ID per deployment so the
    # dev, test and production add-ins can be installed side by side.
    def id = ENV.fetch("SKILL_CAPTURE_ADDIN_ID", "6f0c2a52-7d1e-4c0b-9a8e-3b5f0d9c1e47")
    def version = ENV.fetch("SKILL_CAPTURE_ADDIN_VERSION", "1.0.0.0")
    def provider = ENV.fetch("SKILL_CAPTURE_ADDIN_PROVIDER", "Skill Capture")

    # Public HTTPS origin the add-in is served from. SKILL_CAPTURE_PUBLIC_URL wins
    # (needed behind proxies); otherwise the request's own origin.
    def base_url(request = nil)
      url = ENV["SKILL_CAPTURE_PUBLIC_URL"].presence || request&.base_url || "https://localhost:3000"
      url.chomp("/")
    end
  end
end
