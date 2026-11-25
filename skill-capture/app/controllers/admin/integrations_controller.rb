module Admin
  # The firm's business systems: what is connected, what could be, and the switch.
  class IntegrationsController < BaseController
    before_action :load_integration, only: %i[update destroy]

    def index
      @connected = Integration.recent.includes(:source, :connected_by).to_a
      @connected.each(&:refresh_counts!)
      @catalogue = Capture::Integrations.by_category
      @issued = flash[:issued_token]
      @issued_for = flash[:issued_for]
    end

    def create
      integration, token = Integration.connect!(params[:provider], user: current_user, label: params[:label])
      redirect_to admin_integrations_path, flash: { issued_token: token, issued_for: integration.name }
    rescue ArgumentError, ActiveRecord::RecordInvalid => e
      redirect_to admin_integrations_path, alert: e.message
    end

    def update
      @integration.switch!(params[:enabled])
      @integration.source&.update!(active: @integration.enabled?)
      AuditLog.record("integration.switched", user: current_user, subject: @integration, on: @integration.enabled?)
      redirect_to admin_integrations_path, notice: "#{@integration.name} is #{@integration.enabled? ? 'on' : 'off'}."
    end

    def destroy
      name = @integration.name
      @integration.disconnect!(current_user)
      redirect_to admin_integrations_path, notice: "#{name} disconnected. Events already collected are kept."
    end

    private

    def load_integration
      @integration = Integration.find_by(id: params[:id])
      redirect_to(admin_integrations_path, alert: "No such integration.") if @integration.nil?
    end
  end
end
