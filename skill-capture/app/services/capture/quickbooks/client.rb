require "net/http"

module Capture
  module Quickbooks
    # Talks to one connected company. Refreshes the access token when it is about to
    # expire and writes the rotated refresh token back before using it.
    class Client
      class Error < StandardError; end

      def initialize(integration, http: nil)
        @integration = integration
        @http = http || Net::HTTP
      end

      # "What changed since": the whole connector in one call. Intuit caps the look-back,
      # so a connection left off for longer than that resumes from the edge of the window
      # rather than silently returning nothing.
      def changes_since(time)
        floor = Config.cdc["max_lookback_days"].to_i.days.ago
        since = [time || 7.days.ago, floor].max
        get(format(Config.cdc["path"], realm: @integration.external_id),
            entities: Config.entities.join(","), changedSince: since.utc.iso8601)
      end

      def company_info = get("/v3/company/#{@integration.external_id}/companyinfo/#{@integration.external_id}")

      private

      def get(path, **params)
        refresh_if_needed!
        uri = URI("#{Config.api_base}#{path}")
        uri.query = params.merge(minorversion: Config.minor_version).to_query
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{token!['access_token']}"
        request["Accept"] = "application/json"

        response = @http.start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 30) { |h| h.request(request) }
        case response.code.to_s
        when /\A2/ then JSON.parse(response.body.presence || "{}")
        when "401" then raise Error, "Intuit rejected the token. Reconnect #{@integration.name}."
        when "403" then raise Error, "This app is not allowed to read that company."
        when "429" then raise Error, "Intuit is rate limiting us. The next sweep will pick up where this stopped."
        else raise Error, "Intuit returned #{response.code}"
        end
      rescue JSON::ParserError => e
        raise Error, "Intuit sent something unreadable: #{e.message}"
      rescue SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
        raise Error, "Could not reach Intuit: #{e.class}"
      end

      def token! = @integration.credentials_hash.presence || raise(Error, "#{@integration.name} is not connected")

      # Refresh a little early: a token that expires mid-sweep costs a whole sweep.
      def refresh_if_needed!
        return if @integration.token_expires_at.nil? || @integration.token_expires_at > 2.minutes.from_now
        fresh = Oauth.refresh(token!["refresh_token"], http: @http)
        @integration.store_tokens!(fresh)
      end
    end
  end
end
