# One run of a flow: its steps (copied from the flow when it starts) execute in order. When a task is done
# (by a person in the add-in, or an agent through the API) it records its note and AI usage and hands off:
# the next step becomes ready and is sent to whoever does it, in the app it needs.
#
# Step states: pending → ready (a task waiting on its doer) | paused (a pause step) → done, or skipped.
# The run can start from any task (or run just one), jump to any task while running, skip tasks, take
# new tasks or pauses inserted after the current one, and be put on hold as a whole (no handoffs until
# it's resumed).
class FlowRun < ApplicationRecord
  STATUSES = %w[running on_hold completed cancelled].freeze
  class Error < StandardError; end

  belongs_to :flow
  belongs_to :user
  has_many :skill_runs, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }

  def self.start!(flow, user:, from: 0, only: false)
    from = from.to_i
    raise Error, "No task #{from + 1} in this flow." unless (0...flow.steps.size).cover?(from)
    steps = flow.steps.each_with_index.map do |s, i|
      skipped = i < from || (only && i > from)
      s.merge("state" => skipped ? "skipped" : "pending")
    end
    steps = steps.map { |s| Flow.pause?(s) ? s : s.merge(Capture::Estimator.for_step(s, flow_id: flow.id).slice("nature", "complexity", "engine", "model").compact) }
    run = create!(flow: flow, user: user, status: "running", current_index: from, steps: steps,
                  estimate: Capture::Estimator.for_steps(steps, flow_id: flow.id))
    run.send(:make_ready!, from)
    AuditLog.record("flow.started", user: user, subject: run, flow: flow.name, from: from + 1, only: only)
    run
  end

  def running? = status == "running"
  def active? = %w[running on_hold].include?(status)
  def current = steps[current_index]
  def done_count = steps.count { |s| s["state"] == "done" }
  def owner?(u) = u && (u.id == user_id || u.admin?)

  def split? = Flow.split?(current.to_h)
  def parts = Flow.parts(current.to_h)
  def tally = Capture::Estimator.tally(self)

  # Which parts of the current task this person (or agent) still has to do.
  def my_parts(user: nil, source: nil)
    return [] unless running? && current && current["state"] == "ready"
    parts.each_with_index.select { |p, _| p["state"] != "done" && assigned?(p["assignee"], user: user, source: source) }
  end

  # Can this person (or agent) complete the current task?
  def doer?(user: nil, source: nil)
    s = current
    return false if s.nil? || s["state"] != "ready"
    return my_parts(user: user, source: source).any? if Flow.split?(s)
    a = s["assignee"].to_s
    return source && a == "agent:#{source.id}" if source
    return false unless user
    (a == "me" && user.id == user_id) || a == "user:#{user.id}" || (a.start_with?("agent:") && user.id == user_id) # the owner can stand in for an agent
  end

  def assigned?(a, user: nil, source: nil)
    a = a.to_s
    return a == "agent:#{source.id}" if source
    return false unless user
    (a == "me" && user.id == user_id) || a == "user:#{user.id}" || (a.start_with?("agent:") && user.id == user_id)
  end

  # One part of a split task: two agents, or an AI and a macro, working side by side. The task itself
  # finishes (and hands off) only when every part is done.
  def complete_part!(index:, part_id:, user: nil, source: nil, note: nil, usage: nil)
    with_lock do
      raise Error, status == "on_hold" ? "This flow is paused; resume it first." : "This flow is #{status.humanize.downcase}." unless running?
      raise Error, "Task #{index.to_i + 1} isn't the current task (task #{current_index + 1} is)." unless index.to_i == current_index
      step = current
      raise Error, "Task #{index.to_i + 1} isn't split into parts." unless Flow.split?(step)
      pi = Flow.parts(step).index { |p| p["id"] == part_id.to_s } or raise Error, "No part #{part_id} in this task."
      part = Flow.parts(step)[pi]
      raise Error, "That part is already done." if part["state"] == "done"
      raise Error, "Not your part." unless assigned?(part["assignee"], user: user, source: source)
      u = clean_usage(usage, engine: part["engine"])
      new_parts = Flow.parts(step).deep_dup
      new_parts[pi] = part.merge("state" => "done", "finished_at" => Time.current.iso8601, "note" => note.to_s.strip.first(2000).presence,
                                 "by" => by_label(user, source, part["engine"]), "usage" => u.presence).compact
      set_step(current_index, "parts" => new_parts)
      record_usage!(step, part.merge("engine" => part["engine"]), u, user: user, source: source, part_id: part["id"])
      if new_parts.all? { |p| p["state"] == "done" }
        set_step(current_index, "state" => "done", "finished_at" => Time.current.iso8601,
                                "by" => new_parts.map { |p| p["by"] }.uniq.join(" + "),
                                "note" => new_parts.filter_map { |p| p["note"] }.join(" · ").presence)
        advance!
      end
    end
    AuditLog.record("flow.part_done", user: user, subject: self, step: index.to_i + 1, part: part_id, by_agent: source&.name)
    self
  end

  def complete!(index:, user: nil, source: nil, note: nil, usage: nil)
    with_lock do
      raise Error, status == "on_hold" ? "This flow is paused; resume it first." : "This flow is #{status.humanize.downcase}." unless running?
      raise Error, "Task #{index.to_i + 1} isn't the current task (task #{current_index + 1} is)." unless index.to_i == current_index
      raise Error, "Task #{index.to_i + 1} is a pause; resume it instead." if Flow.pause?(current)
      raise Error, "Task #{index.to_i + 1} is split into parts; finish your part instead." if Flow.split?(current)
      raise Error, "Not your task." unless doer?(user: user, source: source)
      step = current
      u = clean_usage(usage, engine: step["engine"])
      set_step(current_index, "state" => "done", "finished_at" => Time.current.iso8601, "note" => note.to_s.strip.first(2000).presence,
                              "by" => by_label(user, source, step["engine"]), "usage" => u.presence)
      record_usage!(step, step, u, user: user, source: source)
      advance!
    end
    AuditLog.record("flow.step_done", user: user, subject: self, step: index.to_i + 1, by_agent: source&.name)
    self
  end

  # A pause ends: by hand (any manual pause, or a timer early), or when its timer is due.
  def resume_pause!(index:, by: nil)
    with_lock do
      s = steps[index.to_i]
      raise Error, "Task #{index.to_i + 1} isn't a waiting pause." unless index.to_i == current_index && s && s["state"] == "paused"
      raise Error, "Only #{user.name} can resume this." if by && !owner?(by)
      if by.nil? && (!running? || Time.zone.parse(s["resume_at"].to_s).to_i > Time.current.to_i + 1)
        return self # on hold, or a stale timer: not due yet
      end
      set_step(current_index, "state" => "done", "finished_at" => Time.current.iso8601, "by" => by ? by.name : "Timer")
      advance!
    end
    self
  end

  # Put the whole run on hold: no task can be completed and nothing is handed off until it's resumed.
  def hold!(by:)
    raise Error, "Only #{user.name} can pause this run." unless owner?(by)
    with_lock { raise Error, "This flow isn't running." unless running?; update!(status: "on_hold") }
    AuditLog.record("flow.held", user: by, subject: self)
    self
  end

  def release!(by:)
    raise Error, "Only #{user.name} can resume this run." unless owner?(by)
    with_lock { raise Error, "This flow isn't on hold." unless status == "on_hold"; update!(status: "running") }
    AuditLog.record("flow.resumed", user: by, subject: self)
    s = current # a timed pause that came due while on hold ends now
    resume_pause!(index: current_index) if s && s["state"] == "paused" && s["resume_at"] && Time.zone.parse(s["resume_at"]) <= Time.current
    self
  end

  # Deploy a task mid-sequence: make it current now. Going forward skips the tasks in between; going back
  # re-runs from there (later tasks go back to pending).
  def jump_to!(index, by:)
    i = index.to_i
    raise Error, "Only #{user.name} can move this run." unless owner?(by)
    with_lock do
      raise Error, "This flow isn't running." unless active?
      raise Error, "No task #{i + 1}." unless (0...steps.size).cover?(i)
      raise Error, "Task #{i + 1} is already current." if i == current_index
      new = steps.deep_dup
      if i > current_index
        (current_index...i).each { |k| new[k]["state"] = "skipped" unless new[k]["state"] == "done" }
      else
        (i...new.size).each { |k| new[k] = new[k].except("finished_at", "note", "by", "usage", "resume_at").merge("state" => "pending") }
        new[current_index]["state"] = "pending"
      end
      cancel_dispatch!(current_index)
      update!(steps: new, current_index: i)
      make_ready!(i)
    end
    AuditLog.record("flow.jumped", user: by, subject: self, to: i + 1)
    self
  end

  # Skip a task that hasn't run yet (or the current one: the run moves on).
  def skip!(index, by:)
    i = index.to_i
    raise Error, "Only #{user.name} can change this run." unless owner?(by)
    with_lock do
      raise Error, "This flow isn't running." unless active?
      s = steps[i] or raise Error, "No task #{i + 1}."
      raise Error, "Task #{i + 1} has already #{s['state'] == 'done' ? 'run' : 'been skipped'}." unless %w[pending ready paused].include?(s["state"])
      set_step(i, "state" => "skipped")
      if i == current_index
        cancel_dispatch!(i)
        advance!
      end
    end
    self
  end

  # Insert a task or a pause into the run, after the current task (or any later one).
  def insert!(after:, step:, by:)
    a = after.to_i
    raise Error, "Only #{user.name} can change this run." unless owner?(by)
    with_lock do
      raise Error, "This flow isn't running." unless active?
      raise Error, "Insert after the current task or a later one." unless a >= current_index && a < steps.size
      raw = (step.respond_to?(:to_unsafe_h) ? step.to_unsafe_h : step.to_h).stringify_keys
      s = Flow.normalize_step(raw)
      s["app"] = steps[a]["app"] if raw["app"].blank? # a new step sits in the lane of the one before it
      raise Error, "The new task needs a title." if s["title"].blank?
      s["id"] = SecureRandom.hex(4) if steps.any? { |x| x["id"] == s["id"] }
      update!(steps: steps.dup.insert(a + 1, s.merge("state" => "pending", "inserted" => true)))
    end
    self
  end

  def cancel!(by:)
    raise Error, "Only #{user.name} can stop this." unless owner?(by)
    update!(status: "cancelled", finished_at: Time.current)
  end

  def url = Rails.application.routes.url_helpers.flow_run_path(self)

  private

  def by_label(user, source, engine) = engine == "macro" ? "⚙ Macro" : (source ? "🤖 #{source.name}" : user.name)

  def clean_usage(usage, engine: nil)
    u = usage.to_h.stringify_keys.slice("model", "input_tokens", "output_tokens", "duration_ms", "trial_of").compact_blank
    if engine == "macro"
      u = u.slice("duration_ms").merge("model" => "macro", "input_tokens" => 0, "output_tokens" => 0)
    end
    u["cost"] = Capture::Models.cost(u["model"], u["input_tokens"], u["output_tokens"]).to_f if u["model"].present?
    u
  end

  # Every finished task (or part) is measured: what it cost, on which model, and what it was anticipated
  # to cost. A macro records zero tokens and credits the saving to its review.
  def record_usage!(step, unit, usage, user:, source:, part_id: nil)
    engine = unit["engine"].presence || "ai"
    est = Capture::Estimator.for_step(step.merge(unit.slice("engine", "model", "nature")), flow_id: flow_id)
    if engine == "macro" && (review = Capture::MacroScreen.approved_for_step(flow_id, step) || Capture::MacroScreen.approved_for_skill(step["skill_name"]))
      review.record_saving!(est["tokens"].to_i.positive? ? est["tokens"] : Capture::Estimator.for_step(step.merge("engine" => "ai"), flow_id: flow_id)["tokens"])
    end
    draft_macro_from!(step, unit, usage, part_id: part_id) if engine == "ai"
    return unless step["skill_name"].present? && (skill = Skill.current(step["skill_name"]))
    return if engine == "ai" && usage.blank?
    SkillRun.from_report(skill, usage, agent: source ? source.name : "#{user&.name} (flow)", source: source, user: user,
                                       flow_run: self, step_index: current_index).tap do |r|
      r.engine = engine
      r.nature = est["nature"]
      r.part_id = part_id
      r.model = usage["model"].presence || (engine == "macro" ? "macro" : est["model"])
      r.cost = usage["cost"].presence || Capture::Models.cost(r.model, r.input_tokens, r.output_tokens)
      r.estimated_tokens = est["tokens"]
      r.trial_of = usage["trial_of"].presence
      r.save!
    end
  end

  # The AI has just done a scriptable task: ask it to write the script for next time.
  def draft_macro_from!(step, unit, usage, part_id: nil)
    kind, key = part_id ? ["flow_step", "#{flow_id}:#{step['id']}:#{part_id}"] : ["flow_step", "#{flow_id}:#{step['id']}"]
    existing = MacroReview.for_subject(kind, key)
    return if existing&.approved? || existing&.status == "rejected"
    MacroDraftJob.perform_later(kind, key, unit["title"].presence || step["title"],
                                app: step["app"], instructions: unit["instructions"].presence || step["instructions"],
                                skill_name: step["skill_name"], note: unit["note"] || steps[current_index]["note"], usage: usage, run_id: id)
  end

  def set_step(i, attrs)
    new = steps.deep_dup
    new[i] = new[i].merge(attrs).compact
    update!(steps: new)
  end

  # Move to the next pending step, or finish.
  def advance!
    nxt = (current_index + 1...steps.size).find { |k| steps[k]["state"] == "pending" }
    if nxt.nil?
      update!(status: "completed", finished_at: Time.current)
      Notification.create!(user: user, subject: self, kind: "flow", title: "“#{flow.name}” is complete", body: "#{done_count} tasks done.", url: url)
    else
      update!(current_index: nxt)
      make_ready!(nxt)
    end
  end

  # Hand off: a task becomes ready and goes to whoever does it, in the app it needs; a pause starts waiting.
  def make_ready!(i)
    s = steps[i]
    if Flow.pause?(s)
      at = s["pause_mode"] == "timer" ? s["pause_minutes"].to_i.minutes.from_now : nil
      set_step(i, "state" => "paused", "started_at" => Time.current.iso8601, "resume_at" => at&.iso8601)
      if at
        FlowResumeJob.set(wait_until: at).perform_later(id, i)
      else
        Notification.create!(user: user, subject: self, kind: "flow", title: "Paused: #{s['title']}", body: "“#{flow.name}” is waiting for you to resume it before task #{i + 2}.", url: url)
      end
      return
    end
    if Flow.split?(s)
      ready_parts = Flow.parts(s).map { |p| p.merge("state" => p["state"].presence || "ready") }
      set_step(i, "state" => "ready", "started_at" => Time.current.iso8601, "parts" => ready_parts)
      ready_parts.each_with_index { |p, pi| dispatch!(i, s, part: p, part_index: pi) unless p["state"] == "done" }
      return
    end
    set_step(i, "state" => "ready", "started_at" => Time.current.iso8601)
    dispatch!(i, s)
  end

  # Send a task (or one part of it) to whoever does it: an agent's queue, or a person's add-in in the
  # app it needs. A macro travels with its approved script, so the add-in can run it without the AI.
  def dispatch!(i, s, part: nil, part_index: nil)
    unit = part || s
    engine = unit["engine"].presence || "ai"
    review = engine == "macro" ? (Capture::MacroScreen.approved_for_step(flow_id, s) || Capture::MacroScreen.approved_for_skill(s["skill_name"])) : nil
    est = Capture::Estimator.for_step(s.merge(unit.slice("engine", "model", "nature")), flow_id: flow_id)
    prev_i = (0...i).to_a.reverse.find { |k| steps[k]["state"] == "done" && !Flow.pause?(steps[k]) }
    prev = prev_i && steps[prev_i]
    payload = { "flow_run_id" => id, "step_index" => i, "flow" => flow.name, "title" => unit["title"].presence || s["title"], "app" => s["app"],
                "instructions" => unit["instructions"].presence || s["instructions"], "skills" => [s["skill_name"]].compact,
                "previous" => prev && { "title" => prev["title"], "note" => prev["note"], "by" => prev["by"] },
                "engine" => engine, "model" => est["model"], "nature" => est["nature"], "complexity" => est["complexity"],
                "estimate" => est.slice("tokens", "seconds", "cost", "basis"),
                "macro" => review && { "language" => review.language, "code" => review.code, "runnable" => review.runnable_in_addin?, "review_id" => review.id },
                "part_id" => part && part["id"], "part_of" => part && { "task" => s["title"], "parts" => Flow.parts(s).map { |x| x["title"] } },
                "complete_path" => part ? Rails.application.routes.url_helpers.complete_part_api_v1_flow_run_path(id, step: i, part: part["id"])
                                        : Rails.application.routes.url_helpers.complete_api_v1_flow_run_path(id, step: i),
                "note" => "#{part ? "Part #{part_index + 1} of #{Flow.parts(s).size}" : "Task #{i + 1} of #{steps.size}"} in “#{flow.name}”: #{unit['title'].presence || s['title']}" }.compact
    a = unit["assignee"].to_s
    if (src = a[/\Aagent:(\d+)\z/, 1]) && (source = Source.active.find_by(id: src))
      AddinCommand.create!(sender: user, target_source: source, kind: "flow_task", payload: payload, expires_at: 7.days.from_now)
    else
      who = (a.start_with?("user:") && User.find_by(id: a.split(":").last)) || user
      AddinCommand.create!(sender: user, target_user: who, kind: "flow_task", payload: payload, expires_at: 7.days.from_now)
      Notification.create!(user: who, subject: self, kind: "flow", title: "Your turn: #{payload['title']}",
                           body: "#{payload['note']}#{s['app'] != 'Agent' ? ", in #{s['app']}" : ''}#{engine == 'macro' ? ' · runs as a macro, no AI' : ''}#{prev ? ". Handed off by #{prev['by']}." : '.'}", url: url)
    end
  end

  # A task taken off the current slot shouldn't still be waiting in someone's add-in.
  def cancel_dispatch!(i)
    AddinCommand.pending.where(kind: "flow_task").where("payload->>'flow_run_id' = ? AND payload->>'step_index' = ?", id.to_s, i.to_s).update_all(status: "cancelled")
  end
end
