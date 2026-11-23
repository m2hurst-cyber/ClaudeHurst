module Api
  module V1
    # GET /api/v1/route?from=<skill>&to=<skill>: the chain of skills between two skills,
    # for agents and the Step 2 routing engine. Published skills only.
    class RoutesController < BaseController
      def show
        map = Capture::RouteMap.call(user: nil)
        map[:nodes].select! { |n| n[:kind] == "skill" }
        ids = map[:nodes].map { |n| n[:id] }.to_set
        map[:edges].select! { |e| ids.include?(e[:from]) && ids.include?(e[:to]) }
        r = Capture::RoutePlanner.new(map).route(params[:from].to_s, params[:to].to_s)
        return render(json: { error: "no known route" }, status: :not_found) unless r
        render json: { skills: r.keys, legs: r.legs.map { |l| l.slice(:from, :to, :traffic, :manual) },
                       directions: Capture::Directions.for_route(r.keys).map(&:to_h) }
      end
    end
  end
end
