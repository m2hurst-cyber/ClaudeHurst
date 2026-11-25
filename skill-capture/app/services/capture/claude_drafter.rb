require "anthropic"

module Capture
  # Asks Claude to turn a detected workflow into a SKILL.md draft.
  #
  # Privacy: the request carries only workflow structure: the step keys, each
  # step's label, counts and dates. No actor names or ids, resource refs or
  # event context are sent.
  class ClaudeDrafter
    class DraftError < StandardError; end

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You turn workflows observed across an organization's tools into reusable
      "skills": short operating procedures a colleague or an AI agent can follow.

      You receive the ordered steps people repeated, a short label for each step
      as reported by the tool it came from, and how often it was seen. Write the
      skill for someone who has the tools but has never done this task, in
      Anthropic's Agent Skills SKILL.md format:
      - name: lowercase letters, digits and single hyphens, at most 64 characters,
        names the outcome (a gerund like "reconciling-bank-statements" reads well).
        Never use the words "anthropic" or "claude".
      - description: third person, one or two sentences, at most 1024 characters, no
        XML tags. Say what the skill does AND when to use it ("Reconciles … Use when
        …"). Agents choose skills from this text alone, so name the trigger words a
        person would use.
      - body: Markdown under 500 lines, no frontmatter. Start with "# <title>", then
        "## When to use", "## Inputs", "## Steps" (a numbered list, one action per
        step in the imperative, saying what to check before moving on), "## Outputs"
        and "## Checks". Be concise: assume a capable reader and include only what
        they couldn't guess. Do not invent tools, fields or business rules beyond the
        step labels; where a detail is unknown, tell the reader what to confirm.
      - tags: 2-6 lowercase tags.
    PROMPT

    SCHEMA = {
      type: "object",
      additionalProperties: false,
      required: %w[name title description tags inputs outputs body],
      properties: {
        name: { type: "string" },
        title: { type: "string" },
        description: { type: "string" },
        tags: { type: "array", items: { type: "string" } },
        inputs: { type: "array", items: { type: "string" } },
        outputs: { type: "array", items: { type: "string" } },
        body: { type: "string" }
      }
    }.freeze

    def self.call(candidate, client: nil) = new(candidate, client: client).call

    def initialize(candidate, client: nil)
      @c = candidate
      @client = client || Anthropic::Client.new
    end

    # The firm's directions for the size of skill it wants, as agent-facing Markdown.
    # Without this the drafter writes whatever size it feels like and the detector's
    # granularity setting is undone at the last step.
    def level = @level ||= Granularity.level_for(domain: @c.domain, user: @c.requested_by)

    def system_prompt
      g = Granularity.settings(level)
      <<~PROMPT
        #{SYSTEM_PROMPT}
        ## House granularity: #{g[:label].upcase} — #{g[:summary]}

        #{Granularity.directions(level)}
      PROMPT
    end

    def call
      message = @client.beta.messages.create(
        model: Config.llm_model,
        max_tokens: 16_000,
        system_: system_prompt,
        output_config: { effort: :medium, format: { type: :json_schema, schema: SCHEMA } },
        # If a safety classifier declines, retry server-side on a substitute model.
        fallbacks: :default,
        betas: ["server-side-fallback-2026-07-01"],
        messages: [{ role: "user", content: payload.to_json }]
      )
      raise DraftError, "model declined (#{message.stop_details&.category || 'no category'})" if message.stop_reason.to_s == "refusal"
      raise DraftError, "response truncated" if message.stop_reason.to_s == "max_tokens"

      text = message.content.select { |b| b.type.to_s == "text" }.map(&:text).join
      normalize(JSON.parse(text))
    rescue JSON::ParserError => e
      raise DraftError, "unparseable response: #{e.message}"
    end

    private

    def payload
      labels = @c.step_labels
      {
        area: @c.domain,
        times_seen: @c.occurrence_count,
        distinct_people: @c.distinct_actor_count,
        first_seen: @c.first_seen_at&.to_date&.iso8601,
        last_seen: @c.last_seen_at&.to_date&.iso8601,
        steps: @c.steps.map { |s| { action: s, label: labels[s] } },
        requester_notes: @c.origin == "manual" ? @c.draft_description.presence : nil,
        reviewer_notes: @c.review_notes.presence
      }.compact
    end

    def normalize(d)
      name = Naming.skill_name(d["name"])
      {
        name: name.presence || TemplateDrafter.call(@c)[:name],
        title: d["title"].to_s.strip.first(200),
        description: d["description"].to_s.strip.first(1024),
        tags: Array(d["tags"]).map { |t| t.to_s.parameterize }.reject(&:blank?).uniq.first(6),
        inputs: Array(d["inputs"]).map(&:to_s),
        outputs: Array(d["outputs"]).map(&:to_s),
        body: d["body"].to_s
      }
    end
  end
end
