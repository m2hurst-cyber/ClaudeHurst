# Working one return through a playbook: answer the situation questions, follow the route,
# tick steps off, and describe anything new (which becomes a branch for review).
class PlaybookRunsController < ApplicationController
  before_action :set_run, except: :create

  def create
    pb = Capture::Playbook.find(params[:playbook_key])
    raise Capture::Playbook::Error, "Install #{pb.title} first" unless pb.installed?
    run = current_user.playbook_runs.new(playbook_key: pb.key, reference: params[:reference].to_s.squish)
    if run.save
      AuditLog.record("playbook_run.started", user: current_user, subject: run, playbook: pb.key)
      redirect_to playbook_run_path(run)
    else
      redirect_to playbook_path(pb.key), alert: run.errors.full_messages.to_sentence
    end
  rescue Capture::Playbook::Error => e
    redirect_to playbooks_path, alert: e.message
  end

  def show
    @playbook = @run.playbook
    @route = @run.route
    @situations = Situation.for_playbook(@run.playbook_key).to_a
  end

  # PATCH answers[<situation>]=yes|no|unsure
  def update
    keys = Situation.for_playbook(@run.playbook_key).pluck(:key)
    given = params.fetch(:answers, {}).permit(*keys).to_h.select { |_, v| %w[yes no unsure].include?(v) }
    @run.update!(answers: @run.answers.merge(given))
    redirect_to playbook_run_path(@run, anchor: "route"), notice: "Route updated."
  end

  # POST step=<skill name> done=1|0
  def step
    name = params[:step].to_s
    raise ActiveRecord::RecordNotFound unless @run.route.any? { |r| r[:name] == name && !r[:pending] }
    done = ActiveModel::Type::Boolean.new.cast(params[:done]) ? (@run.done | [name]) : (@run.done - [name])
    @run.update!(done: done)
    redirect_to playbook_run_path(@run, anchor: "step-#{name}")
  end

  # POST text=<what's different about this client's year>
  def situation
    outcome, sit, r = Capture::Situations.describe!(@run, params[:text], user: current_user)
    who = r.by == "ai" ? "The AI" : "The rules"
    msg = if outcome == :matched
      "#{who} matched that to an existing situation: “#{sit.question}” It's now on this return's route."
    else
      "New situation proposed: “#{sit.question}” A branch draft went to the tax reviewers; it joins the route for every return once published."
    end
    redirect_to playbook_run_path(@run, anchor: "situations"), notice: msg
  rescue ArgumentError => e
    redirect_to playbook_run_path(@run, anchor: "situations"), alert: e.message
  end

  # POST: load this return's route into my Office add-in's memory.
  def send_route
    names = @run.route.reject { |r| r[:pending] }.map { |r| r[:name] }.first(20)
    cmd = AddinCommand.create!(sender: current_user, target_user: current_user, kind: "load_route",
                               payload: { "skills" => names, "titles" => names.filter_map { |n| Skill.current(n)&.title }, "note" => "Return #{@run.reference}" })
    AuditLog.record("skill.sent", user: current_user, subject: cmd, to: "self", skills: names)
    redirect_to playbook_run_path(@run), notice: "Sent #{names.size} skills to your Office add-in. Open Skill Capture in Excel, Word or Outlook to use them."
  end

  def complete
    @run.update!(status: "completed", completed_at: Time.current)
    redirect_to playbooks_path, notice: "Return #{@run.reference} completed."
  end

  private

  def set_run = @run = current_user.playbook_runs.find(params[:id])
end
