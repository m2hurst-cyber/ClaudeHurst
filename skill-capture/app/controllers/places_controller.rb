# Directions for roads, intersections and handoffs on the route map.
# GET /map/places/:key(.md|.json)  ·  GET /map/search?q=
class PlacesController < ApplicationController
  before_action :set_place, only: %i[show edit update]
  before_action :require_editor, only: %i[edit update]

  def show
    respond_to do |format|
      format.html
      format.json { render json: @place.to_h.merge(editable: editable?, url: place_path(@place.key)) }
      format.md { render plain: @place.body, content_type: "text/markdown" }
    end
  end

  def edit; end

  def update
    p = params.require(:place).permit(:title, :body, :tags, :note)
    Capture::Directions.save!(@place, title: p[:title], body: p[:body], tags: p[:tags].to_s.split(","), note: p[:note], user: current_user)
    redirect_to place_path(@place.key), notice: "Directions saved."
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.message
    @place.body = p[:body]
    render :edit, status: :unprocessable_entity
  end

  def search
    @q = params[:q].to_s
    @hits = Capture::MapSearch.call(@q)
    respond_to do |format|
      format.html
      format.json { render json: @hits.map { |h| h.to_h.merge(url: place_path(h.key)) } }
    end
  end

  private

  def set_place
    @place = Capture::Directions.find(params[:key])
  rescue Capture::Directions::NotFound => e
    respond_to do |format|
      format.html { redirect_to skill_map_path, alert: e.message }
      format.any { render json: { error: e.message }, status: :not_found }
    end
  end

  def editable? = Capture::Directions.editable_by?(current_user, @place)
  helper_method :editable?

  def require_editor
    raise Pundit::NotAuthorizedError unless editable?
  end
end
