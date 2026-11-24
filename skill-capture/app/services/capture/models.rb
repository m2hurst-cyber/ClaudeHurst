module Capture
  # The model catalogue and what work costs on it. Tiers run macro → small → standard → deep; a task's
  # nature and complexity pick the tier (TaskProfile), and the cheapest live model in that tier is the
  # one suggested, unless someone names another.
  module Models
    module_function

    DEFAULTS = [
      { key: "macro", name: "Office macro (no AI)", tier: "macro", input_cost: 0, output_cost: 0, tokens_per_second: 1_000_000,
        notes: "A reviewed, deterministic script. No tokens: the work runs in Excel, Word or PowerPoint.", position: 0 },
      { key: "claude-haiku-5-5", name: "Haiku 5.5", tier: "small", input_cost: 1.0, output_cost: 5.0, tokens_per_second: 160,
        notes: "Fast and cheap: linear steps, extraction, formatting, checks.", position: 1 },
      { key: "claude-sonnet-5-5", name: "Sonnet 5.5", tier: "standard", input_cost: 3.0, output_cost: 15.0, tokens_per_second: 90,
        notes: "Everyday analysis, drafting, multi-step work with clear rules.", position: 2 },
      { key: "claude-opus-5-5", name: "Opus 5.5", tier: "deep", input_cost: 15.0, output_cost: 75.0, tokens_per_second: 55,
        notes: "Judgment, ambiguity, difficult writing and reasoning.", position: 3 }
    ].freeze

    def ensure_defaults!
      DEFAULTS.each do |d|
        m = ModelProfile.find_or_initialize_by(key: d[:key])
        m.assign_attributes(d.except(:key)) if m.new_record?
        m.save!
      end
      ModelProfile.live
    end

    def catalogue = (ModelProfile.live.to_a.presence || (ensure_defaults! && ModelProfile.live.to_a))
    def find(key) = catalogue.find { |m| m.key == key }
    def for_tier(tier) = catalogue.select { |m| m.tier == tier }.min_by(&:position) || catalogue.find { |m| m.tier == "standard" } || catalogue.last
    def label(key) = find(key)&.name || key.to_s
    def cost(key, input_tokens, output_tokens) = find(key)&.cost_for(input_tokens, output_tokens) || 0.to_d
    def seconds(key, tokens) = (tokens.to_f / (find(key)&.tokens_per_second || 90)).round(1)
  end
end
