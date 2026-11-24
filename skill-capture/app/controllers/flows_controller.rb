# Flows: sequence tasks across apps and agents on a process map, then run them in order.
class FlowsController < ApplicationController
  before_action :set_flow, only: %i[show update destroy run]

  def index
    @flows = Flow.where(user: current_user).order(updated_at: :desc)
    @runs = FlowRun.where(user: current_user).includes(:flow).order(created_at: :desc).limit(20)
    @assigned = FlowRun.where(status: "running").where.not(user: current_user).includes(:flow, :user).select { |r| r.doer?(user: current_user) }
  end

  def new
    @flow = params[:template].present? ? Flow.from_template(params[:template], user: current_user, agent: Source.active.find_by(kind: "integration")) : Flow.new(user: current_user, name: "New flow", steps: [])
    if @flow.steps.any? && @flow.save
      redirect_to flow_path(@flow), notice: "Created from the template. Drag tasks to reorder or move them between lanes."
    else
      @flow.steps = [{ "id" => SecureRandom.hex(4), "title" => "First task", "app" => "Excel", "assignee" => "me" }]
      @flow.save!
      redirect_to flow_path(@flow)
    end
  end

  def show
    return render_markdown(Capture::LlmMarkdown.flow(@flow), @flow.name) if request.format.md?
    @palette = Skill.published.visible_to(current_user).order(:title).limit(400).to_a
    @classes = SkillClassification.where(skill_name: @palette.map(&:name)).index_by(&:skill_name)
    @agents = Source.active.where(kind: "integration").order(:name)
    @people = User.where.not(id: current_user.id).order(:name)
    @runs = @flow.runs.order(created_at: :desc).limit(10)
    @estimate = @flow.estimate
    @macros = MacroReview.where(subject_kind: "flow_step", subject_key: @flow.steps.map { |s| "#{@flow.id}:#{s['id']}" }).index_by { |r| r.subject_key.split(":").last }
    @live = @flow.runs.where(status: %w[running on_hold]).order(created_at: :desc).first
  end

  def update
    @flow.assign_attributes(name: params[:name].presence || @flow.name, description: params[:description], steps: Flow.normalize_steps(params[:steps]))
    if @flow.save
      respond_to do |f|
        f.json { render json: { ok: true, steps: @flow.steps, estimate: @flow.estimate } }
        f.html { redirect_to flow_path(@flow), notice: "Saved." }
      end
    else
      respond_to do |f|
        f.json { render json: { error: @flow.errors.full_messages.to_sentence }, status: :unprocessable_entity }
        f.html { redirect_to flow_path(@flow), alert: @flow.errors.full_messages.to_sentence }
      end
    end
  end

  def destroy
    @flow.destroy!
    redirect_to flows_path, notice: "Deleted."
  end

  def run
    r = FlowRun.start!(@flow, user: current_user, from: params[:from].to_i, only: params[:only] == "1")
    redirect_to flow_run_path(r), notice: params[:only] == "1" ? "Running just task #{r.current_index + 1}." : "Started at task #{r.current_index + 1}."
  rescue FlowRun::Error => e
    redirect_to flow_path(@flow), alert: e.message
  end

  private

  def set_flow
    @flow = Flow.find(params[:id])
    raise Pundit::NotAuthorizedError unless @flow.visible_to?(current_user)
  end
end
