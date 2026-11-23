# Rest stops: restorable snapshots of a skill. Make one by hand, look at one, pin it, revert to it.
class RestStopsController < ApplicationController
  before_action :set_stop, except: :create

  def create
    skill = Skill.find(params[:skill_id])
    raise Pundit::NotAuthorizedError unless Capture::RestStops.can_capture?(current_user, skill)
    stop = Capture::RestStops.capture!(skill, reason: "manual", kind: "manual", user: current_user, label: params[:label])
    AuditLog.record("rest_stop.created", user: current_user, subject: skill, rest_stop: stop.id)
    redirect_to skill_path(Skill.current(skill.name) || skill, anchor: "rest-stops"), notice: "Rest stop saved."
  end

  def show
    @current = Skill.current(@stop.skill_name)
    respond_to do |f|
      f.html
      f.json do
        send_data JSON.pretty_generate(@stop.as_json(except: %w[skill_id])), filename: "#{@stop.skill_name}-rest-stop-#{@stop.id}.json", type: :json
      end
    end
  end

  def update
    raise Pundit::NotAuthorizedError unless Capture::RestStops.can_revert?(current_user, @skill)
    @stop.update!(pinned: ActiveModel::Type::Boolean.new.cast(params[:pinned]))
    redirect_back fallback_location: rest_stop_path(@stop), notice: @stop.pinned ? "Pinned: it won't be pruned." : "Unpinned."
  end

  def revert
    skill = Capture::RestStops.revert!(@stop, user: current_user)
    redirect_to skill_path(skill, anchor: "rest-stops"), notice: "Reverted to rest stop ##{@stop.id}: published as v#{skill.version}. The state before the revert is saved as a rest stop too."
  rescue Capture::RestStops::Error, Capture::Publisher::Error => e
    redirect_to rest_stop_path(@stop), alert: e.message
  end

  private

  def set_stop
    @stop = RestStop.find(params[:id])
    @skill = Skill.current(@stop.skill_name) || Skill.where(name: @stop.skill_name).order(version: :desc).first
    raise Pundit::NotAuthorizedError unless @skill&.visible_to?(current_user)
  end
end
