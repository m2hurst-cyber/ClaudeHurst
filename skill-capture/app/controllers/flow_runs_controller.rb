class FlowRunsController < ApplicationController
  before_action :set_run

  def show; end

  def complete
    @run.complete!(index: params[:step].to_i, user: current_user, note: params[:note])
    redirect_to flow_run_path(@run), notice: @run.status == "completed" ? "Done: every task is complete." : "Handed off to task #{@run.current_index + 1}: #{@run.current['title']}."
  rescue FlowRun::Error => e
    redirect_to flow_run_path(@run), alert: e.message
  end

  def cancel
    @run.cancel!(by: current_user)
    redirect_to flow_run_path(@run), notice: "Stopped."
  rescue FlowRun::Error => e
    redirect_to flow_run_path(@run), alert: e.message
  end

  private

  def set_run
    @run = FlowRun.find(params[:id])
    ok = @run.user_id == current_user.id || current_user.admin? || @run.steps.any? { |s| s["assignee"] == "user:#{current_user.id}" }
    raise Pundit::NotAuthorizedError unless ok
  end
end
