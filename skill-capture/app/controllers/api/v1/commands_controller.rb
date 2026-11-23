module Api
  module V1
    # Agent integrations receive skills routed to them from the map.
    #   GET /api/v1/commands               pending commands with bundles (marks them delivered)
    #   GET /api/v1/bundles/:name          one skill's bundle
    #   GET /api/v1/resources              resources agents may read
    #   GET /api/v1/resources/<folder/path/slug>  the file (or a redirect for links)
    class CommandsController < BaseController
      def index
        cmds = AddinCommand.pending.where(target_source: current_source).order(:created_at).limit(10).to_a
        out = cmds.map do |c|
          c.update!(status: "delivered", delivered_at: Time.current, delivered_to: current_source.name)
          { id: c.id, kind: c.kind, from: c.sender&.name, note: c.payload["note"],
            bundles: Capture::Bundle.for_names(c.skill_names, viewer: nil, url_for: ->(r) { api_v1_resource_url(r.key.delete_prefix("resource:")) }) }
        end
        render json: out
      end

      def bundle
        skill = Skill.current(params[:id])
        raise ActiveRecord::RecordNotFound unless skill&.shared?
        render json: Capture::Bundle.for(skill, viewer: nil, url_for: ->(r) { api_v1_resource_url(r.key.delete_prefix("resource:")) })
      end

      def resources
        folders = ResourceFolder.includes(:parent).select { |f| f.visible_to?(nil) }
        render json: Resource.where(folder_id: folders.map(&:id)).includes(folder: :parent).map { |r|
          Capture::ResourceLibrary.describe(r, download_url: api_v1_resource_url(r.key.delete_prefix("resource:")))
        }
      end

      def resource
        r = Resource.find_by_key("resource:#{params[:path]}")
        raise ActiveRecord::RecordNotFound unless r&.agents_can_read?
        return redirect_to(r.url, allow_other_host: true) if r.kind == "link"
        send_data r.content, filename: r.filename, type: r.content_type, disposition: "attachment"
      end
    end
  end
end
