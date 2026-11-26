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
      # RENDER_EXTERNAL_URL and FLY_APP_NAME are set by those hosts, so a fresh deployment
      # serves a correct manifest before anyone has configured anything.
      url = ENV["SKILL_CAPTURE_PUBLIC_URL"].presence ||
            ENV["RENDER_EXTERNAL_URL"].presence ||
            (ENV["FLY_APP_NAME"].presence && "https://#{ENV['FLY_APP_NAME']}.fly.dev") ||
            request&.base_url || "https://localhost:3000"
      normalise(url)
    end

    # A host can hand us a bare hostname rather than a URL — Render's `property: host`
    # gives "example.onrender.com" — and a manifest built from that has no scheme, so
    # Office cannot fetch a single icon or the pane itself. Assume https, because Office
    # will not load an add-in over anything else.
    def normalise(url)
      url = url.to_s.strip.chomp("/")
      return url if url.start_with?("https://")
      return url.sub(/\Ahttp:/, "https:") if url.start_with?("http://localhost", "http://127.0.0.1")
      return url if url.start_with?("http://") # a deliberate local choice; leave it alone
      "https://#{url}"
    end
  end
end
