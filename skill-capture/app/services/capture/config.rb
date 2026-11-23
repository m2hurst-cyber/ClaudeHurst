module Capture
  # Capture sensitivity, privacy and retention knobs. All overridable by env var.
  module Config
    module_function

    def enabled? = ENV.fetch("SKILL_CAPTURE_ENABLED", "true") == "true"

    # A workflow becomes a candidate once seen this many times ...
    def min_occurrences = ENV.fetch("SKILL_CAPTURE_MIN_OCCURRENCES", 3).to_i
    # ... by at least this many distinct people.
    def min_actors = ENV.fetch("SKILL_CAPTURE_MIN_ACTORS", 1).to_i
    def min_steps = ENV.fetch("SKILL_CAPTURE_MIN_STEPS", 2).to_i
    def max_steps = ENV.fetch("SKILL_CAPTURE_MAX_STEPS", 6).to_i
    # Idle gap that ends a work session.
    def session_gap = ENV.fetch("SKILL_CAPTURE_SESSION_GAP_MINUTES", 30).to_i.minutes
    def lookback = ENV.fetch("SKILL_CAPTURE_LOOKBACK_DAYS", 30).to_i.days
    def retention = ENV.fetch("SKILL_CAPTURE_RETENTION_DAYS", 90).to_i.days
    def max_batch = ENV.fetch("SKILL_CAPTURE_MAX_BATCH", 500).to_i
    def publish_alert_threshold = ENV.fetch("SKILL_CAPTURE_PUBLISH_ALERT_PER_HOUR", 10).to_i
    def ingest_alert_threshold = ENV.fetch("SKILL_CAPTURE_INGEST_ALERT_PER_HOUR", 50_000).to_i

    # The only context keys kept from incoming events. Values must be short tokens.
    def context_keys
      ENV.fetch("SKILL_CAPTURE_CONTEXT_KEYS", "app,status,stage,channel,kind,format,file_type,template").split(",").map(&:strip)
    end

    def llm_enabled?
      ENV["SKILL_CAPTURE_LLM"] != "off" && (ENV["ANTHROPIC_API_KEY"].present? || ENV["ANTHROPIC_AUTH_TOKEN"].present?)
    end

    def llm_model = ENV.fetch("SKILL_CAPTURE_MODEL", "claude-opus-5-5")
  end
end
