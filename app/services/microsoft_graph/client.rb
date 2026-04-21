module MicrosoftGraph
  class Client
    GRAPH_ROOT = "https://graph.microsoft.com/v1.0".freeze
    TOKEN_ROOT = "https://login.microsoftonline.com".freeze

    class Error < StandardError; end

    def initialize(connection: nil)
      @connection = connection
    end

    def self.authorization_url(state:, scopes: default_scopes)
      tenant = ENV.fetch("MICROSOFT_TENANT_ID", "common")
      query = {
        client_id: ENV.fetch("MICROSOFT_CLIENT_ID"),
        response_type: "code",
        redirect_uri: ENV.fetch("MICROSOFT_REDIRECT_URI"),
        response_mode: "query",
        scope: scopes.join(" "),
        state: state
      }

      "#{TOKEN_ROOT}/#{tenant}/oauth2/v2.0/authorize?#{URI.encode_www_form(query)}"
    end

    def self.exchange_code(code)
      tenant = ENV.fetch("MICROSOFT_TENANT_ID", "common")
      response = Faraday.post("#{TOKEN_ROOT}/#{tenant}/oauth2/v2.0/token") do |request|
        request.headers["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = URI.encode_www_form(
          client_id: ENV.fetch("MICROSOFT_CLIENT_ID"),
          client_secret: ENV.fetch("MICROSOFT_CLIENT_SECRET"),
          code: code,
          redirect_uri: ENV.fetch("MICROSOFT_REDIRECT_URI"),
          grant_type: "authorization_code"
        )
      end

      parse_response(response)
    end

    def self.default_scopes
      %w[offline_access User.Read Mail.Send Calendars.ReadWrite ChannelMessage.Send]
    end

    def me
      get("/me")
    end

    def post(path, body)
      response = http.post("#{GRAPH_ROOT}#{path}") do |request|
        request.headers["Authorization"] = "Bearer #{bearer_value}"
        request.headers["Content-Type"] = "application/json"
        request.body = body.to_json
      end

      self.class.parse_response(response)
    end

    def get(path)
      response = http.get("#{GRAPH_ROOT}#{path}") do |request|
        request.headers["Authorization"] = "Bearer #{bearer_value}"
      end

      self.class.parse_response(response)
    end

    def self.parse_response(response)
      body = response.body.present? ? JSON.parse(response.body) : {}
      return body if response.success?

      message = body.dig("error", "message") || body["error_description"] || response.reason_phrase
      raise Error, "Microsoft Graph request failed: #{message}"
    rescue JSON::ParserError
      raise Error, "Microsoft Graph returned non-JSON response with status #{response.status}"
    end

    private

    attr_reader :connection

    def http
      @http ||= Faraday.new
    end

    def bearer_value
      payload = JSON.parse(connection.integration_payload.to_s)
      payload.fetch("access_value")
    end
  end
end
