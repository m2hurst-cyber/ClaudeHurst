module Api
  module V1
    module Addin
      class ResourcesController < BaseController
        def download
          r = Resource.find(params[:id])
          raise ActiveRecord::RecordNotFound unless r.visible_to?(current_user)
          return redirect_to(r.url, allow_other_host: true) if r.kind == "link"
          send_data r.content, filename: r.filename, type: r.content_type, disposition: "attachment"
        end
      end
    end
  end
end
