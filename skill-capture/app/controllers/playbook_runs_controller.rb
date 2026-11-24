# A return worked through a playbook: the filer uploads documents, answers the situation questions,
# and the AI prepares each leg of the road; a leg is done only when its checks verify it.
# Visible to the filer and the reviewer they choose, nobody else.
class PlaybookRunsController < ApplicationController
  before_action :set_run, except: :create
  before_action :filer_only, only: %i[update inputs prepare attest acknowledge request_review situation send_route complete generate deliver]

  def create
    pb = Capture::Playbook.find(params[:playbook_key])
    raise Capture::Playbook::Error, "Install #{pb.title} first" unless pb.installed?
    run = current_user.playbook_runs.new(playbook_key: pb.key, reference: params[:reference].to_s.squish)
    if run.save
      AuditLog.record("playbook_run.started", user: current_user, subject: run, playbook: pb.key)
      Capture::Legs.new(run).verify_all! if pb.prepares_legs?
      redirect_to playbook_run_path(run)
    else
      redirect_to playbook_path(pb.key), alert: run.errors.full_messages.to_sentence
    end
  rescue Capture::Playbook::Error => e
    redirect_to playbooks_path, alert: e.message
  end

  def show
    @playbook = @run.playbook
    @legs = Capture::Legs.new(@run)
    @route = @run.route
    @situations = Situation.for_playbook(@run.playbook_key).to_a
    @documents = @run.documents.ordered.to_a
    @reviewers = User.active.where(role: %w[reviewer admin]).where.not(id: @run.user_id).select { |u| u.reviews?(@playbook.area) }
  end

  # PATCH answers[<situation>]=yes|no|unsure
  def update
    keys = Situation.for_playbook(@run.playbook_key).pluck(:key)
    given = params.fetch(:answers, {}).permit(*keys).to_h.select { |_, v| %w[yes no unsure].include?(v) }
    @run.update!(answers: @run.answers.merge(given))
    reverify
    redirect_to playbook_run_path(@run, anchor: "route"), notice: "Route updated."
  end

  # PATCH inputs[<key>]=value: figures and choices the filer enters
  def inputs
    allowed = @run.playbook.leg_specs.fetch("inputs", {})
    given = params.fetch(:inputs, {}).permit(*allowed.keys).to_h.transform_values { |v| v.to_s.strip.first(60) }
    @run.update!(inputs: @run.inputs.merge(given).reject { |_, v| v.blank? })
    reverify
    redirect_to playbook_run_path(@run, anchor: "leg-#{params[:leg]}")
  end

  # POST leg=<skill>: the AI (or rules) prepares the leg, then every leg is re-verified
  def prepare
    @legs = Capture::Legs.new(@run)
    state = @legs.prepare!(params[:leg].to_s, user: current_user)
    who = state["prepared_by"] == "ai" ? "The AI prepared" : "Prepared"
    msg = state["status"] == "verified" ? "#{who} the leg and it verified." : "#{who} the leg. #{Array(state['checks']).count { |c| !c['ok'] }} check(s) still open."
    redirect_to playbook_run_path(@run, anchor: "leg-#{params[:leg]}"), notice: msg
  rescue ArgumentError => e
    redirect_to playbook_run_path(@run), alert: e.message
  end

  # POST leg, key, value=1|0: the filer confirms (or withdraws) an attestation
  def attest
    leg = params[:leg].to_s
    keys = Array(@run.playbook.leg_spec(leg)["checks"]).flat_map { |c| [c["key"], c["unless_attested"]] }.compact
    raise ActiveRecord::RecordNotFound unless keys.include?(params[:key])
    state = @run.leg(leg)
    attested = (state["attested"] || {}).merge(params[:key] => (params[:value] == "1" ? { "by" => current_user.id, "at" => Time.current.iso8601 } : nil)).compact
    @run.legs = @run.legs.merge(leg => state.merge("attested" => attested))
    @run.save!
    reverify
    redirect_to playbook_run_path(@run, anchor: "leg-#{leg}")
  end

  # POST leg, index: the filer has dealt with a blocking issue the preparer raised
  def acknowledge
    leg = params[:leg].to_s
    state = @run.leg(leg)
    i = params[:index].to_i
    raise ActiveRecord::RecordNotFound unless Array(state["issues"])[i]
    @run.legs = @run.legs.merge(leg => state.merge("acknowledged" => (Array(state["acknowledged"]) | [i])))
    @run.save!
    AuditLog.record("return.issue_acknowledged", user: current_user, subject: @run, leg: leg, issue: state["issues"][i]["text"])
    reverify
    redirect_to playbook_run_path(@run, anchor: "leg-#{leg}")
  end

  # POST: the K-1 generator makes one statement per partner from the confirmed allocations
  def generate
    made = Capture::K1Generator.generate!(@run, user: current_user)
    redirect_to playbook_run_path(@run, anchor: "leg-generate-schedule-k1s"), notice: "Generated #{made.size} K-1s, tied to the Form 1065."
  rescue Capture::K1Generator::Error => e
    redirect_to playbook_run_path(@run, anchor: "leg-generate-schedule-k1s"), alert: e.message
  end

  # POST document_id, target_id: send a generated K-1 into one of my individual returns (the handoff)
  def deliver
    k1 = @run.documents.find(params[:document_id])
    target = current_user.playbook_runs.find(params[:target_id])
    copy = Capture::K1Generator.deliver!(k1, target, user: current_user)
    redirect_to playbook_run_path(@run, anchor: "leg-generate-schedule-k1s"),
                notice: "Sent #{k1.label} to return #{target.reference} as #{copy.label}; its K-1 branch is now on that return's road."
  rescue Capture::K1Generator::Error => e
    redirect_to playbook_run_path(@run, anchor: "leg-generate-schedule-k1s"), alert: e.message
  end

  def request_review
    reviewer = User.active.find(params[:reviewer_id])
    raise Pundit::NotAuthorizedError if reviewer.id == @run.user_id || !reviewer.reviews?(@run.playbook.area)
    @run.update!(reviewer: reviewer, reviewed_at: nil)
    Notification.create!(user: reviewer, subject: @run, kind: "return_review", title: "#{current_user.name} asked you to review return #{@run.reference}",
                         url: playbook_run_path(@run, anchor: "leg-review-the-individual-return"))
    reverify
    redirect_to playbook_run_path(@run, anchor: "leg-review-the-individual-return"), notice: "#{reviewer.name} will review the return."
  end

  # The reviewer signs off (or withdraws it).
  def sign_off
    raise Pundit::NotAuthorizedError unless @run.reviewer_id == current_user.id
    @run.update!(reviewed_at: params[:withdraw] ? nil : Time.current)
    AuditLog.record(params[:withdraw] ? "return.signoff_withdrawn" : "return.signed_off", user: current_user, subject: @run)
    reverify
    redirect_to playbook_run_path(@run, anchor: "leg-review-the-individual-return"), notice: params[:withdraw] ? "Sign-off withdrawn." : "Signed off."
  end

  # POST text=<what's different about this client's year>
  def situation
    outcome, sit, r = Capture::Situations.describe!(@run, params[:text], user: current_user)
    reverify
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
    done, total = @run.progress
    return redirect_to(playbook_run_path(@run), alert: "Every leg must be verified first (#{done} of #{total}).") if done < total
    @run.update!(status: "completed", completed_at: Time.current)
    redirect_to playbooks_path, notice: "Return #{@run.reference} completed."
  end

  private

  def set_run
    @run = PlaybookRun.find(params[:id])
    raise ActiveRecord::RecordNotFound unless @run.visible_to?(current_user)
  end

  def filer_only
    raise Pundit::NotAuthorizedError unless @run.user_id == current_user.id
  end

  def reverify = (Capture::Legs.new(@run).verify_all! if @run.playbook.prepares_legs?)
end
