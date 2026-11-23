module Api
  module V1
    module Addin
      class SessionsController < BaseController
        # GET /api/v1/addin/me
        def show
          render json: {
            name: current_user.name,
            role: current_user.role,
            domains: current_user.domains,
            reviewer: current_user.admin? || current_user.reviewer?,
            capture_enabled: Capture::Config.enabled?,
            console_url: root_url,
            open_reviews: current_user.admin? || current_user.reviewer? ? policy_scope(SkillCandidate).open.count : 0
          }
        end

        # DELETE /api/v1/addin/me — disconnect this Office install
        def destroy
          current_token.revoke!
          AuditLog.record("addin.revoked", user: current_user, subject: current_token)
          head :no_content
        end
      end
    end
  end
end
