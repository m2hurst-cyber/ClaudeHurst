class FlowRunsController < ApplicationController
  before_action :set_run

  def show
    respond_to do |f|
      f.html
      f.md { render_markdown(Capture::LlmMarkdown.run(@run), "#{@run.flow.name}-run-#{@run.id}") }
      f.json { render json: { status: @run.status, current_index: @run.current_index, states: @run.steps.map { |s| s["state"] }, updated_at: @run.updated_at.to_f } }
    end
  end

  def complete
    change("Done.") { @run.complete!(index: params[:step].to_i, user: current_user, note: params[:note]) }
  end

  def resume = change("Resumed.") { @run.resume_pause!(index: params[:step].to_i, by: current_user) }
  def hold = change("Paused: nothing is handed off until you resume.") { @run.hold!(by: current_user) }
  def release = change("Resumed.") { @run.release!(by: current_user) }
  def jump = change("Task #{params[:step].to_i + 1} is now current.") { @run.jump_to!(params[:step], by: current_user) }
  def skip = change("Skipped task #{params[:step].to_i + 1}.") { @run.skip!(params[:step], by: current_user) }

  def insert
    step = params.permit(:title, :app, :assignee, :kind, :pause_mode, :pause_minutes, :instructions).to_h
    change(step["kind"] == "pause" ? "Pause inserted." : "Task inserted.") { @run.insert!(after: params[:after], step: step, by: current_user) }
  end

  def cancel = change("Stopped.") { @run.cancel!(by: current_user) }

  private

  def change(msg)
    yield
    msg = @run.status == "completed" ? "Done: every task is complete." : "#{msg} Now: task #{@run.current_index + 1}, #{@run.current&.dig('title')}." if action_name.in?(%w[complete resume skip])
    redirect_to flow_run_path(@run), notice: msg
  rescue FlowRun::Error => e
    redirect_to flow_run_path(@run), alert: e.message
  end

  def set_run
    @run = FlowRun.find(params[:id])
    ok = @run.user_id == current_user.id || current_user.admin? || @run.steps.any? { |s| s["assignee"] == "user:#{current_user.id}" }
    raise Pundit::NotAuthorizedError unless ok
  end
end
