module SkillCapture
  # Central knobs for capture sensitivity, privacy and retention.
  # Every value can be overridden with an env var so ops can tune without a deploy.
  module Config
    module_function

    def enabled?
      ENV.fetch("SKILL_CAPTURE_ENABLED", "true") == "true"
    end

    # A workflow becomes a candidate once it has been seen this many times
    # (counted once per work session) ...
    def min_occurrences = ENV.fetch("SKILL_CAPTURE_MIN_OCCURRENCES", 3).to_i
    # ... by at least this many distinct people.
    def min_users = ENV.fetch("SKILL_CAPTURE_MIN_USERS", 1).to_i
    # Steps per workflow. Single actions are not skills; very long chains are noise.
    def min_steps = ENV.fetch("SKILL_CAPTURE_MIN_STEPS", 2).to_i
    def max_steps = ENV.fetch("SKILL_CAPTURE_MAX_STEPS", 6).to_i
    # Idle gap that ends a work session.
    def session_gap = ENV.fetch("SKILL_CAPTURE_SESSION_GAP_MINUTES", 30).to_i.minutes
    # How far back the detector looks, and how long raw events are retained.
    def lookback = ENV.fetch("SKILL_CAPTURE_LOOKBACK_DAYS", 30).to_i.days
    def retention = ENV.fetch("SKILL_CAPTURE_RETENTION_DAYS", 90).to_i.days
    # Misuse alert: more than this many publishes by one user in an hour.
    def publish_alert_threshold = ENV.fetch("SKILL_CAPTURE_PUBLISH_ALERT_PER_HOUR", 10).to_i

    # Controllers never captured: auth, the capture/review UI itself, admin and pure UI chrome.
    EXCLUDED_CONTROLLERS = %w[
      devise/sessions devise/passwords devise/registrations
      skill_candidates skills notifications dashboards
      admin/users admin/audit_logs rails/health
    ].freeze

    # Only these context keys are ever stored. Values are restricted to ids / enums;
    # free text, names, emails, amounts and notes are never captured.
    CONTEXT_ALLOWLIST = %w[status stage channel recurrence kind activity_type format].freeze

    def llm_enabled?
      ENV["SKILL_CAPTURE_LLM"] != "off" &&
        (ENV["ANTHROPIC_API_KEY"].present? || ENV["ANTHROPIC_AUTH_TOKEN"].present?)
    end

    def llm_model = ENV.fetch("SKILL_CAPTURE_MODEL", "claude-opus-5-5")
  end
end
