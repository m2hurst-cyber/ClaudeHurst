# The route map of know-how (default) and the by-area overview.
class SkillMapsController < ApplicationController
  # GET /map: road network of skills, with journeys, branches and improvements
  def show
    @map = Capture::RouteMap.call(user: current_user)
    @schedule = PricingSchedule.current
    respond_to do |format|
      format.html
      format.json { render json: @map }
    end
  end

  # GET /map/route?from=a&to=b: turn-by-turn chain of skills
  def route
    map = Capture::RouteMap.call(user: current_user)
    r = Capture::RoutePlanner.new(map).route(params[:from].to_s, params[:to].to_s)
    nodes = map[:nodes].index_by { |n| n[:id] }
    if r
      render json: { found: true, keys: r.keys, legs: r.legs,
                     directions: Capture::Directions.for_route(r.keys.reject { |k| k.start_with?("candidate:") }).map { |pl| pl.to_h.except(:markdown).merge(url: place_path(pl.key)) }, stops: r.keys.map { |k| nodes[k].slice(:id, :title, :area, :kind, :url, :apps, :steps, :tier, :price, :median_minutes) } }
    else
      render json: { found: false }
    end
  end

  # GET /map/areas: where skills live, by area
  def areas
    @areas = Capture::SkillMap.call
    @max = [@areas.map(&:total).max.to_i, 1].max
    respond_to do |format|
      format.html
      format.json do
        render json: @areas.map { |a|
          a.to_h.slice(:name, :published, :awaiting_review, :detected, :apps).merge(
            total: a.total, reviewers: a.reviewers, contributors: a.contributors, gaps: a.gaps)
        }
      end
    end
  end
end
