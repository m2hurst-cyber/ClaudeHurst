module Admin
  class ProtocolsController < BaseController
    def show = @protocols = Protocol.all_keys

    def update
      @protocols = Protocol.all_keys
      raw = params.fetch(:protocols, {}).permit!.to_h
      ok = Protocol.transaction do
        @protocols.each do |p|
          values = raw.fetch(p.key, {})
          p.enabled = ActiveModel::Type::Boolean.new.cast(values["enabled"]) || false
          p.assign_settings(values)
        end
        @protocols.all?(&:valid?) && @protocols.each(&:save!)
      end
      if ok
        AuditLog.record("protocols.updated", user: current_user, protocols: @protocols.to_h { |p| [p.key, p.settings.merge("enabled" => p.enabled)] })
        redirect_to admin_protocols_path, notice: "Protocols saved."
      else
        render :show, status: :unprocessable_entity
      end
    end
  end
end
