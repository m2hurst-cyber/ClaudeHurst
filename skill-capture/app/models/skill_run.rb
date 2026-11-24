# One run of a skill by an AI agent (or by Claude in the add-in, or a flow step): which model, how many
# tokens in and out, how long. Every run updates the skill's usage; Capture::Intensity rolls them up.
class SkillRun < ApplicationRecord
  STATUSES = %w[succeeded failed].freeze
  MAX_TOKENS = 50_000_000
  MAX_DURATION_MS = 7.days.in_milliseconds

  belongs_to :source, optional: true
  belongs_to :user, optional: true
  belongs_to :flow_run, optional: true

  validates :skill_name, :agent, presence: true
  validates :agent, length: { maximum: 100 }
  validates :model, length: { maximum: 100 }, format: { with: %r{\A[\w.\-:@/\[\] ]+\z}, allow_blank: true }
  validates :input_tokens, :output_tokens, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_TOKENS }
  validates :duration_ms, numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: MAX_DURATION_MS }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }

  before_validation { self.occurred_at ||= Time.current }

  def total_tokens = input_tokens + output_tokens

  # Build from an agent's report (API params). Accepts duration_ms, or started_at + finished_at.
  def self.from_report(skill, params, **attrs)
    p = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
    p = p.stringify_keys
    dur = p["duration_ms"].presence&.to_i
    if dur.nil? && p["started_at"].present? && p["finished_at"].present?
      dur = ((Time.zone.parse(p["finished_at"]) - Time.zone.parse(p["started_at"])) * 1000).round rescue nil
    end
    new(skill_name: skill.name, skill_version: (p["version"].presence || skill.version).to_i, model: p["model"].to_s.strip.presence,
        input_tokens: p["input_tokens"].to_i, output_tokens: p["output_tokens"].to_i, duration_ms: dur,
        status: p["status"].presence || "succeeded", **attrs)
  end
end
