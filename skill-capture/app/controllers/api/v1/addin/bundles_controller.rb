module Api
  module V1
    module Addin
      # GET /api/v1/addin/bundles/:name: a single skill's bundle (for "Add to memory")
      class BundlesController < BaseController
        def show
          skill = Skill.current(params[:id])
          raise ActiveRecord::RecordNotFound unless skill&.visible_to?(current_user)
          render json: Capture::Bundle.for(skill, viewer: current_user, url_for: ->(r) { download_api_v1_addin_resource_url(r) })
        end
      end
    end
  end
end
