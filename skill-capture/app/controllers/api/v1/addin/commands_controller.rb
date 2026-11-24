module Api
  module V1
    module Addin
      # The running add-in checks in here; skills sent to this person arrive as bundles
      # (SKILL.md + directions + resources) for its local memory.
      class CommandsController < BaseController
        # GET /api/v1/addin/commands?host=Excel&platform=PC
        def index
          # A flow task waits for the add-in in the app it needs (a PowerPoint task isn't delivered to Excel).
          cmds = AddinCommand.pending.where(target_user: current_user).order(:created_at).limit(20).to_a
                             .select { |c| c.kind != "flow_task" || !::Flow::LANES.first(5).include?(c.payload["app"]) || c.payload["app"] == params[:host] }.first(10)
          where = [params[:host].presence, params[:platform].presence].compact.join(" on ").presence || "Office"
          out = cmds.map do |c|
            c.update!(status: "delivered", delivered_at: Time.current, delivered_to: where)
            { id: c.id, kind: c.kind, from: c.sender&.name, note: c.payload["note"], task: c.kind == "flow_task" ? c.payload.except("complete_path") : nil,
              bundles: Capture::Bundle.for_names(c.skill_names, viewer: current_user, url_for: ->(r) { download_api_v1_addin_resource_url(r) }) }
          end
          render json: out
        end
      end
    end
  end
end
