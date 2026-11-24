# One run of a flow: its steps (copied from the flow when it starts) execute in order. When a step is
# done (by a person in the add-in, or an agent through the API), it records its note and AI usage and
# hands off: the next step becomes ready and is sent to whoever does it, in the app it needs.
class FlowRun < ApplicationRecord
  STATUSES = %w[running completed cancelled].freeze
  class Error < StandardError; end

  belongs_to :flow
  belongs_to :user
  has_many :skill_runs, dependent: :nullify

  validates :status, inclusion: { in: STATUSES }

  def self.start!(flow, user:)
    run = create!(flow: flow, user: user, status: "running", current_index: 0,
                  steps: flow.steps.map { |s| s.merge("state" => "pending") })
    run.send(:make_ready!, 0)
    AuditLog.record("flow.started", user: user, subject: run, flow: flow.name, steps: flow.steps.size)
    run
  end

  def running? = status == "running"
  def current = steps[current_index]
  def done_count = steps.count { |s| s["state"] == "done" }

  # Can this person (or agent) complete the current step?
  def doer?(user: nil, source: nil)
    a = current&.dig("assignee").to_s
    return source && a == "agent:#{source.id}" if source
    return false unless user
    (a == "me" && user.id == user_id) || a == "user:#{user.id}" || (a.start_with?("agent:") && user.id == user_id) # the owner can stand in for an agent
  end

  def complete!(index:, user: nil, source: nil, note: nil, usage: nil)
    with_lock do
      raise Error, "This flow is #{status}." unless running?
      raise Error, "Task #{index.to_i + 1} isn't the current task (task #{current_index + 1} is)." unless index.to_i == current_index
      raise Error, "Not your task." unless doer?(user: user, source: source)
      step = steps[current_index]
      u = usage.to_h.stringify_keys.slice("model", "input_tokens", "output_tokens", "duration_ms").compact_blank
      new_steps = steps.deep_dup
      new_steps[current_index] = step.merge("state" => "done", "finished_at" => Time.current.iso8601, "note" => note.to_s.strip.first(2000).presence,
                                            "by" => source ? "🤖 #{source.name}" : user.name, "usage" => u.presence).compact
      if step["skill_name"] && u.present? && (skill = Skill.current(step["skill_name"]))
        SkillRun.from_report(skill, u, agent: source ? source.name : "#{user.name} (flow)", source: source, user: user, flow_run: self, step_index: current_index).save!
      end
      nxt = current_index + 1
      if nxt >= steps.size
        update!(steps: new_steps, status: "completed", finished_at: Time.current)
      else
        update!(steps: new_steps, current_index: nxt)
        make_ready!(nxt)
      end
    end
    if status == "completed"
      Notification.create!(user: user_id == user&.id ? self.user : self.user, subject: self, kind: "flow", title: "“#{flow.name}” is complete", body: "All #{steps.size} tasks done.", url: url)
    end
    AuditLog.record("flow.step_done", user: user, subject: self, step: index.to_i + 1, by_agent: source&.name)
    self
  end

  def cancel!(by:)
    raise Error, "Only #{user.name} can stop this." unless by.id == user_id || by.admin?
    update!(status: "cancelled", finished_at: Time.current)
  end

  def url = Rails.application.routes.url_helpers.flow_run_path(self)

  private

  # Hand off: mark the step ready and send it to whoever does it, in the app it needs.
  def make_ready!(i)
    s = steps[i]
    s2 = steps.deep_dup
    s2[i] = s.merge("state" => "ready", "started_at" => Time.current.iso8601)
    update!(steps: s2)
    prev = i.positive? ? steps[i - 1] : nil
    payload = { "flow_run_id" => id, "step_index" => i, "flow" => flow.name, "title" => s["title"], "app" => s["app"],
                "instructions" => s["instructions"], "skills" => [s["skill_name"]].compact,
                "previous" => prev && { "title" => prev["title"], "note" => prev["note"], "by" => prev["by"] },
                "complete_path" => Rails.application.routes.url_helpers.complete_api_v1_flow_run_path(id, step: i),
                "note" => "Task #{i + 1} of #{steps.size} in “#{flow.name}”: #{s['title']}" }
    a = s["assignee"].to_s
    if (src = a[/\Aagent:(\d+)\z/, 1]) && (source = Source.active.find_by(id: src))
      AddinCommand.create!(sender: user, target_source: source, kind: "flow_task", payload: payload, expires_at: 7.days.from_now)
    else
      who = a.start_with?("user:") ? User.find_by(id: a.split(":").last) : user
      who ||= user
      AddinCommand.create!(sender: user, target_user: who, kind: "flow_task", payload: payload, expires_at: 7.days.from_now)
      Notification.create!(user: who, subject: self, kind: "flow", title: "Your turn: #{s['title']}",
                           body: "Task #{i + 1} of #{steps.size} in “#{flow.name}”#{s['app'] != 'Agent' ? ", in #{s['app']}" : ''}#{prev ? ". Handed off by #{prev['by']}." : '.'}", url: url)
    end
  end
end
