module Admin
  class SourcesController < BaseController
    def index = @sources = Source.order(:name)
    def new = @source = Source.new(kind: "custom")

    def create
      @source, @token = Source.issue!(**params.require(:source).permit(:name, :kind).to_h.symbolize_keys, created_by: current_user)
      AuditLog.record("source.created", user: current_user, source: @source)
      render :created
    rescue ActiveRecord::RecordInvalid => e
      @source = e.record
      render :new, status: :unprocessable_entity
    end

    def deactivate
      source = Source.find(params[:id])
      source.update!(active: false)
      AuditLog.record("source.deactivated", user: current_user, source: source)
      redirect_to admin_sources_path, notice: "#{source.name} can no longer send events."
    end
  end
end
