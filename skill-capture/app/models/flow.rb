# A sequence of tasks across apps and agents, laid out on a process map (lanes = where the work happens,
# order = left to right). Each step names its app, who does it (me, a coworker, or an agent integration),
# an optional skill to follow, and instructions. Runs execute the steps in order; see FlowRun.
class Flow < ApplicationRecord
  LANES = %w[Excel Word PowerPoint Outlook Teams Agent].freeze
  MAX_STEPS = 50

  belongs_to :user
  has_many :runs, class_name: "FlowRun", dependent: :destroy

  validates :name, presence: true, length: { maximum: 120 }
  validate :steps_ok

  TEMPLATES = {
    "research-report" => {
      name: "Research report: data to deck",
      description: "Collect and analyze data in Excel, write the white paper in Word, build the deck and its appendix in PowerPoint.",
      steps: [
        ["Collect data", "Excel", "me", nil, "Pull the series into a raw data sheet; note the source and date of each."],
        ["Analyze data", "Excel", "agent", nil, "Summary statistics for each variable; flag gaps and outliers."],
        ["Clean data", "Excel", "agent", nil, "Fix types, fill or drop gaps as noted, remove duplicates; keep a log of changes."],
        ["Regression analysis on Y", "Excel", "agent", nil, "Regress Y on the chosen variables; report coefficients, standard errors, R² and residual checks."],
        ["Chart data", "Excel", "me", nil, "Chart Y, the fitted values and the key drivers."],
        ["Identify key trends and label them in cells", "Agent", "agent", nil, "Write a one-line label next to each key trend, in the cells beside the data."],
        ["Write the white paper", "Word", "agent", nil, "Draft the white paper from the analysis and labels: summary, method, findings, limits."],
        ["Create the PowerPoint deck", "PowerPoint", "me", "board-deck-design", "Build the deck from the white paper's findings."],
        ["Collect existing charts from Excel into an appendix", "PowerPoint", "me", "charts-to-ppt-appendix", "Copy every chart from the workbook into appendix slides, one per slide, with its title and source."]
      ]
    }
  }.freeze

  def self.from_template(key, user:, agent: nil)
    t = TEMPLATES.fetch(key)
    new(user: user, name: t[:name], description: t[:description],
        steps: t[:steps].map do |title, lane, who, skill, text|
          { "id" => SecureRandom.hex(4), "title" => title, "app" => lane,
            "assignee" => who == "agent" ? (agent ? "agent:#{agent.id}" : "me") : "me",
            "skill_name" => (skill if skill && Skill.current(skill)&.visible_to?(user)), "instructions" => text }.compact
        end)
  end

  def visible_to?(u) = u && (u.id == user_id || u.admin?)

  # Who: "me" (the person running it), "user:<id>", or "agent:<source id>".
  def self.assignee_label(a, owner: nil)
    case a.to_s
    when "me", "" then owner ? owner.name : "Me"
    when /\Auser:(\d+)\z/ then User.find_by(id: $1)&.name || "Unknown person"
    when /\Aagent:(\d+)\z/ then "🤖 #{Source.find_by(id: $1)&.name || 'Unknown agent'}"
    else a.to_s
    end
  end

  def self.normalize_steps(list) = Array(list).first(MAX_STEPS).map { |s| normalize_step(s) }

  # A step is a task (done by a person or an agent) or a pause: "manual" waits until someone resumes it,
  # "timer" resumes by itself after pause_minutes.
  def self.normalize_step(s)
    s = (s.respond_to?(:to_unsafe_h) ? s.to_unsafe_h : s.to_h).stringify_keys
    pause = s["kind"] == "pause"
    { "id" => s["id"].to_s.gsub(/[^a-z0-9]/i, "").first(16).presence || SecureRandom.hex(4),
      "kind" => pause ? "pause" : nil,
      "title" => s["title"].to_s.squish.first(160).presence || (pause ? "Pause" : ""), "app" => s["app"].to_s.presence_in(LANES) || "Agent",
      "assignee" => pause ? "me" : (s["assignee"].to_s.match?(/\A(me|user:\d+|agent:\d+)\z/) ? s["assignee"].to_s : "me"),
      "skill_name" => (s["skill_name"].to_s.presence unless pause), "instructions" => s["instructions"].to_s.strip.first(2000).presence,
      "pause_mode" => (pause ? (s["pause_mode"] == "timer" ? "timer" : "manual") : nil),
      "pause_minutes" => (pause && s["pause_mode"] == "timer" ? s["pause_minutes"].to_i.clamp(1, 10_080) : nil) }.compact
  end

  def self.pause?(s) = s["kind"] == "pause"
  def self.pause_label(s) = s["pause_mode"] == "timer" ? "Wait #{ActiveSupport::Duration.build(s['pause_minutes'].to_i * 60).inspect}" : "Wait until resumed"

  private

  def steps_ok
    errors.add(:steps, "need at least one task") if steps.blank?
    errors.add(:steps, "at most #{MAX_STEPS}") if steps.size > MAX_STEPS
    steps.each_with_index do |s, i|
      errors.add(:steps, "task #{i + 1} needs a title") if s["title"].blank?
      errors.add(:steps, "task #{i + 1}: unknown skill #{s['skill_name']}") if s["skill_name"] && !Skill.current(s["skill_name"])
      if (src = s["assignee"].to_s[/\Aagent:(\d+)\z/, 1]) && !Source.active.exists?(id: src, kind: "integration")
        errors.add(:steps, "task #{i + 1}: that agent isn't an active integration")
      end
    end
    errors.add(:steps, "have duplicate ids") if steps.map { |s| s["id"] }.uniq.size != steps.size
  end
end
