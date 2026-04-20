module Admin
  class AuditLogsController < BaseController
    def index
      scope = AuditLog.includes(:user).recent
      scope = scope.where(action: params[:action_filter]) if params[:action_filter].present?
      @pagy, @logs = pagy(scope)
    end

    def show
      @log = AuditLog.find(params[:id])
    end
  end
end
