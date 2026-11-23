module Api
  module V1
    # Agents read directions for a place, or search the map.
    #   GET /api/v1/places/<key>(.md)   e.g. junction:export-trial-balance, handoff:a>b
    #   GET /api/v1/search?q=
    class PlacesController < BaseController
      def show
        place = Capture::Directions.find(params[:key], viewer: nil)
        if request.format.symbol == :md
          render plain: place.body, content_type: "text/markdown"
        else
          render json: place.to_h
        end
      rescue Capture::Directions::NotFound => e
        render json: { error: e.message }, status: :not_found
      end

      def search
        render json: Capture::MapSearch.call(params[:q], viewer: nil).map(&:to_h)
      end
    end
  end
end
