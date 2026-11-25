require "net/http"

module Capture
  module Quickbooks
    # The authorization-code dance, and the part everyone gets wrong afterwards: Intuit
    # rotates the refresh token every time it is used, so the new one must be stored or
    # the connection dies silently in a few weeks.
    module Oauth
      class Error < StandardError; end

      module_function

      def authorize_url(state:)
        params = { client_id: Config.client_id, response_type: "code", scope: Config.scope,
                   redirect_uri: Config.redirect_uri, state: state }
        "#{Config.authorize_url}?#{params.to_query}"
      end

      # A state we can check on the way back without keeping server-side state for it.
      def state_for(user) = Rails.application.message_verifier(:quickbooks).generate({ "user_id" => user.id, "at" => Time.current.to_i })

      # String keys on purpose: the message serializer is JSON, so symbol keys come back
      # as strings and a symbol lookup here would quietly reject every state we signed.
      def user_from_state(state)
        payload = Rails.application.message_verifier(:quickbooks).verified(state.to_s)&.with_indifferent_access
        return nil if payload.nil? || payload[:at].to_i < 1.hour.ago.to_i
        User.active.find_by(id: payload[:user_id])
      end

      def exchange(code, http: nil) = token_request({ grant_type: "authorization_code", code: code, redirect_uri: Config.redirect_uri }, http: http)
      def refresh(refresh_token, http: nil) = token_request({ grant_type: "refresh_token", refresh_token: refresh_token }, http: http)

      def token_request(body, http: nil)
        uri = URI(Config.token_url)
        request = Net::HTTP::Post.new(uri)
        request.basic_auth(Config.client_id.to_s, Config.client_secret.to_s)
        request["Accept"] = "application/json"
        request.set_form_data(body)

        response = (http || Net::HTTP).start(uri.host, uri.port, use_ssl: true, open_timeout: 10, read_timeout: 20) { |h| h.request(request) }
        parsed = JSON.parse(response.body.presence || "{}") rescue {}
        unless response.code.to_s.start_with?("2")
          raise Error, friendly(response.code.to_s, parsed)
        end
        { access_token: parsed["access_token"], refresh_token: parsed["refresh_token"],
          expires_at: Time.current + parsed["expires_in"].to_i.seconds }
      rescue SocketError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
        raise Error, "Could not reach Intuit: #{e.class}"
      end

      def friendly(code, parsed)
        detail = parsed["error_description"].presence || parsed["error"].presence
        case code
        when "400" then "Intuit refused the request#{": #{detail}" if detail}. If this says invalid_grant the authorisation has already been used or has expired."
        when "401" then "Intuit did not accept this app's client id and secret."
        else "Intuit returned #{code}#{": #{detail}" if detail}"
        end
      end
    end
  end
end
