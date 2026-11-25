module Capture
  module Quickbooks
    # Everything Intuit-specific that is a string rather than behaviour, in one place.
    # The app's own credentials come from the environment; never from the repository.
    module Config
      module_function

      # The API details live with the rest of that provider's manifest, so one file
      # describes a system completely: what it is, what it produces, what it needs, and
      # how to reach it.
      def file = Integrations.find("quickbooks")&.api || {}

      def verified? = file["verified"] == true
      def authorize_url = file["authorize_url"]
      def token_url = file["token_url"]
      def revoke_url = file["revoke_url"]
      def scope = file["scope"]
      def minor_version = file["minor_version"]
      def cdc = file["cdc"]
      def entities = Array(cdc["entities"])

      def sandbox? = ENV.fetch("QUICKBOOKS_ENV", "sandbox") != "production"
      def api_base = file.dig("api_base", sandbox? ? "sandbox" : "production")

      def client_id = ENV["QUICKBOOKS_CLIENT_ID"]
      def client_secret = ENV["QUICKBOOKS_CLIENT_SECRET"]
      def webhook_verifier = ENV["QUICKBOOKS_WEBHOOK_VERIFIER"]
      def redirect_uri = ENV["QUICKBOOKS_REDIRECT_URI"]

      # Say which one is missing rather than failing at the far end of a redirect.
      def missing = Integrations.find("quickbooks").missing_credentials.map { |c| c["env"] } - ["QUICKBOOKS_WEBHOOK_VERIFIER"]
      def configured? = missing.empty?
    end
  end
end
