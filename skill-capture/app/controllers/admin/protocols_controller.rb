module Admin
  class ProtocolsController < BaseController
    before_action :load_page, only: %i[show update]

    def show; end

    # What each granularity setting would have produced from the events we already hold.
    # A dial whose effect nobody can see is not a control.
    def preview
      render json: Capture::Granularity.preview
    end

    def update
      raw = params.fetch(:protocols, {}).permit!.to_h
      ok = Protocol.transaction do
        @protocols.each do |p|
          values = raw.fetch(p.key, {})
          p.enabled = ActiveModel::Type::Boolean.new.cast(values["enabled"]) || false
          p.assign_settings(values)
        end
        @protocols.all?(&:valid?) && @protocols.each(&:save!)
      end
      params.fetch(:granularity_by_area, {}).permit!.to_h.each do |area, level|
        GranularityOverride.set!("domain", area, level.presence)
      end
      if ok
        AuditLog.record("protocols.updated", user: current_user, protocols: @protocols.to_h { |p| [p.key, p.settings.merge("enabled" => p.enabled)] })
        redirect_to admin_protocols_path, notice: "Protocols saved."
      else
        render :show, status: :unprocessable_entity
      end
    end

    private

    def load_page
      @protocols = Protocol.all_keys
      @overrides = GranularityOverride.domains
      @areas = (Skill.distinct.pluck(:domain) + SkillCandidate.distinct.pluck(:domain)).compact.uniq.sort
    end
  end
end
