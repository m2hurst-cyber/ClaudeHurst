module Api
  module V1
    module Addin
      # The running add-in checks in here; skills sent to this person arrive as bundles
      # (SKILL.md + directions + resources) for its local memory.
      class CommandsController < BaseController
        # GET /api/v1/addin/commands?host=Excel&platform=PC
        def index
          cmds = AddinCommand.pending.where(target_user: current_user).order(:created_at).limit(10).to_a
          where = [params[:host].presence, params[:platform].presence].compact.join(" on ").presence || "Office"
          out = cmds.map do |c|
            c.update!(status: "delivered", delivered_at: Time.current, delivered_to: where)
            { id: c.id, kind: c.kind, from: c.sender&.name, note: c.payload["note"],
              bundles: Capture::Bundle.for_names(c.skill_names, viewer: current_user, url_for: ->(r) { download_api_v1_addin_resource_url(r) }) }
          end
          render json: out
        end
      end
    end
  end
end
