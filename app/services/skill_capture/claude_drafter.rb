require "anthropic"

module SkillCapture
  # Asks Claude to turn a detected workflow into a SKILL.md draft.
  #
  # Privacy: the request carries only workflow structure (step keys, the
  # catalog's description of each step, counts and dates). No record contents,
  # names, emails or free text from users is ever sent.
  class ClaudeDrafter
    class DraftError < StandardError; end

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You turn workflows observed in a beverage co-packer's CRM-ERP into reusable
      "skills": short operating procedures that a colleague or an AI agent can follow.

      You receive the ordered steps a team repeated, a description of what each step
      does in the app, and how often it was seen. Write the skill for someone who has
      app access but has never done this task:
      - name: kebab-case, at most 64 characters, describes the outcome.
      - description: one or two sentences saying what the skill does AND when to use
        it, at most 1024 characters. Agents choose skills from this text alone.
      - body: Markdown with sections "When to use", "Inputs", "Steps" (numbered,
        one app action per step, say what to check before moving on), "Outputs",
        and "Checks". Do not invent screens, fields or business rules beyond the
        step descriptions; where a detail is unknown, say what to confirm instead.
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

    def call
      message = @client.beta.messages.create(
        model: Config.llm_model,
        max_tokens: 16_000,
        system_: SYSTEM_PROMPT,
        output_config: { effort: :medium, format: { type: :json_schema, schema: SCHEMA } },
        # Server-side fallback: if a safety classifier declines, retry on a substitute model.
        fallbacks: :default,
        betas: ["server-side-fallback-2026-07-01"],
        messages: [{ role: "user", content: payload.to_json }]
      )

      if message.stop_reason.to_s == "refusal"
        raise DraftError, "model declined (#{message.stop_details&.category || 'no category'})"
      end
      raise DraftError, "response truncated" if message.stop_reason.to_s == "max_tokens"

      text = message.content.select { |b| b.type.to_s == "text" }.map(&:text).join
      data = JSON.parse(text)
      normalize(data)
    rescue JSON::ParserError => e
      raise DraftError, "unparseable response: #{e.message}"
    end

    private

    def payload
      {
        area: @c.domain,
        times_seen: @c.occurrence_count,
        distinct_people: @c.distinct_user_count,
        first_seen: @c.first_seen_at&.to_date&.iso8601,
        last_seen: @c.last_seen_at&.to_date&.iso8601,
        steps: @c.steps.map { |s| { app_action: s, what_it_does: Catalog.describe(s) } },
        reviewer_notes: @c.review_notes.presence
      }.compact
    end

    def normalize(d)
      name = d["name"].to_s.parameterize.first(64).sub(/-+\z/, "")
      name = TemplateDrafter.call(@c)[:name] if name.blank?
      {
        name: name,
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
