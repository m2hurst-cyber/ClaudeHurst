module Api
  module V1
    module Addin
      # The Office add-in calls these endpoints as the signed-in person:
      # `Authorization: Bearer sca_...` (issued by AddinConnectController).
      class BaseController < ActionController::API
        include Pundit::Authorization

        before_action :authenticate_addin!

        rescue_from ActiveRecord::RecordNotFound do
          render json: { error: "not found" }, status: :not_found
        end
        rescue_from Pundit::NotAuthorizedError do
          render json: { error: "not allowed" }, status: :forbidden
        end

        private

        attr_reader :current_user, :current_token

        def authenticate_addin!
          token = request.authorization.to_s[/\ABearer (.+)\z/, 1]
          @current_token = AddinToken.authenticate(token)
          @current_user = @current_token&.user
          render json: { error: "not connected" }, status: :unauthorized unless @current_user
        end

        def pundit_user = current_user
      end
    end
  end
end
