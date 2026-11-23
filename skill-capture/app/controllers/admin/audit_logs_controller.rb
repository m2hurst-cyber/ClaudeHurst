module Admin
  class AuditLogsController < BaseController
    def index
      scope = AuditLog.includes(:user, :source).recent
      scope = scope.where("action LIKE ?", "#{AuditLog.sanitize_sql_like(params[:q])}%") if params[:q].present?
      @pagy, @logs = pagy(scope, limit: 50)
    end
  end
end
