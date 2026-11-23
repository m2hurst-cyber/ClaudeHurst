module Api
  module V1
    module Addin
      # Areas with published skills, for the Library's area filter.
      class AreasController < BaseController
        def index
          areas = Capture::SkillMap.call.select { |a| a.published.positive? && !a.unassigned? }
          render json: areas.map { |a| { name: a.name, published: a.published } }
        end
      end
    end
  end
end
