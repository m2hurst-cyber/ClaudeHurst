module Api
  module V1
    # Collectors and agents authenticate with a Source token: `Authorization: Bearer sc_...`.
    class BaseController < ActionController::API
      before_action :authenticate_source!

      rescue_from ActiveRecord::RecordNotFound do
        render json: { error: "not found" }, status: :not_found
      end

      private

      attr_reader :current_source

      def authenticate_source!
        token = request.authorization.to_s[/\ABearer (.+)\z/, 1]
        @current_source = Source.authenticate(token)
        render json: { error: "invalid or inactive token" }, status: :unauthorized unless @current_source
      end
    end
  end
end
