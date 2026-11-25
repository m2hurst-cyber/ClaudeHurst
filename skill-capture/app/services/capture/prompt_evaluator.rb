require "anthropic"

module Capture
  # Judges a pattern a trigger found before anyone is prompted: is it a real, reusable skill
  # (or a real improvement to one), which of save / extend / branch fits, and what would it be
  # called? Its title and description are written in the Agent Skills format and become the
  # draft's defaults if the person accepts.
  #
  # Claude when configured (structured output, low effort); otherwise rules: the trigger's
  # thresholds stand and the title comes from the step labels.
  #
  # Privacy: only step keys and labels, counts, and the base skill's title, description and
  # steps are sent. Never who did the work, documents or values.
  class PromptEvaluator
    Result = Struct.new(:worthwhile, :kind, :confidence, :title, :description, :rationale, :by, keyword_init: true)

    SYSTEM_TEMPLATE = <<~PROMPT.freeze
      You review patterns found in one person's work in Microsoft Office before they are asked
      whether to turn it into a "skill" (a reusable procedure a colleague or an AI agent follows).

      Kinds:
      - save: a workflow they repeat that no skill covers. Worth it only if it is a coherent task
        with a recognizable outcome, not incidental navigation or noise (opening, switching, undoing).
      - extend: they finish an existing skill and then keep doing extra steps. Worth it if the extra
        steps plausibly belong to that skill's outcome (they'd help everyone), not a different task.
      - branch: they do an existing skill differently. Worth it if their way is a genuine alternative
        (a different method, tool or shortcut), not a mistake or a partial run.
      You may change the kind (an "extend" whose steps are really a separate task is a "save"; a branch
      everyone should adopt could be an "extend").

      HOUSE GRANULARITY — %<granularity>s. Judge "worthwhile" against the directions below:
      a pattern at the wrong size for this firm is not worth raising, however often it recurs.

      %<guidance>s

      Write title and description in Anthropic's Agent Skills format: the title names the outcome in a
      few words; the description is third person, at most 1024 characters, no XML tags, and says what the
      skill does and when to use it ("Reconciles … Use when …"). Give a confidence from 0 to 100 and a
      one-sentence rationale the person will see.
    PROMPT

    SCHEMA = {
      type: "object", additionalProperties: false,
      required: %w[worthwhile kind confidence title description rationale],
      properties: {
        worthwhile: { type: "boolean" },
        kind: { type: "string", enum: SkillPrompt::KINDS },
        confidence: { type: "integer" },
        title: { type: "string" },
        description: { type: "string" },
        rationale: { type: "string" }
      }
    }.freeze

    def self.call(prompt, client: nil) = new(prompt, client: client).call

    def initialize(prompt, client: nil)
      @p = prompt
      @client = client
    end

    def call
      if @client || (Config.llm_enabled? && Protocol.for("evaluation").enabled)
        begin
          return claude
        rescue ClaudeDrafter::DraftError, Anthropic::Errors::Error, JSON::ParserError => e
          Rails.logger.warn("Prompt ##{@p.id}: AI evaluation failed, using rules. #{e.class}: #{e.message}")
        end
      end
      rules
    end

    private

    def payload
      s = @p.skill
      {
        kind: @p.kind, times_seen: @p.occurrences,
        steps: @p.steps.zip(@p.step_labels).map { |k, l| { action: k, label: l } },
        added_steps: @p.added_labels.presence, skipped_steps: @p.removed_labels.presence,
        existing_skill: s && { title: s.title, description: s.description,
                               steps: @p.labels(Array(s.source["workflow"])) }
      }.compact
    end

    # The house granularity is part of the instruction, so the model applies the same taste
    # the detector does rather than its own idea of how big a skill should be.
    def level
      @level ||= Granularity.level_for(domain: @p.skill&.domain || @p.user&.domains&.first, user: @p.user)
    end

    def system_prompt
      g = Granularity.settings(level)
      format(SYSTEM_TEMPLATE, granularity: "#{g[:label].downcase} (#{g[:summary].downcase})",
                              guidance: Granularity.directions(level))
    end

    def claude
      msg = (@client || Anthropic::Client.new).beta.messages.create(
        model: Config.llm_model, max_tokens: 4_000, system_: system_prompt,
        output_config: { effort: :low, format: { type: :json_schema, schema: SCHEMA } },
        fallbacks: :default, betas: ["server-side-fallback-2026-07-01"],
        messages: [{ role: "user", content: payload.to_json }]
      )
      raise ClaudeDrafter::DraftError, "model declined" if msg.stop_reason.to_s == "refusal"
      d = JSON.parse(msg.content.select { |b| b.type.to_s == "text" }.map(&:text).join)
      kind = SkillPrompt::KINDS.include?(d["kind"]) ? d["kind"] : @p.kind
      kind = @p.kind if kind != "save" && @p.skill_name.nil? # extend/branch need a skill to build on
      std = SkillStandard.normalize(title: d["title"].to_s.squish.first(120), name: d["title"].to_s, description: d["description"].to_s, body: "")
      Result.new(worthwhile: d["worthwhile"] == true, kind: kind, confidence: d["confidence"].to_i.clamp(0, 100),
                 title: d["title"].to_s.squish.first(120), description: std[:description], rationale: d["rationale"].to_s.squish.first(300), by: "ai")
    end

    def rules
      s = @p.skill
      labels = @p.step_labels.map { |l| l.to_s.sub(/[.\s]+\z/, "") }
      title, desc, why =
        case @p.kind
        when "save"
          t = labels.size <= 3 ? labels.join(", then ") : "#{labels.first} through #{labels.last.sub(/\A./) { |c| c.downcase }}"
          [t, "Performs #{labels.size} steps: #{labels.join('; ')}.", "Repeated #{@p.occurrences} times and not covered by any skill."]
        when "extend"
          [s.title, "#{s.description.sub(/[.\s]*\z/, '.')} Finishes with: #{@p.added_labels.join('; ')}.",
           "You added the same #{@p.added_labels.size == 1 ? 'step' : 'steps'} after this skill #{@p.occurrences} times."]
        when "branch"
          ["#{s.title} (#{@p.added_labels.first || 'variant'})",
           "A variant of #{s.title.sub(/\A./) { |c| c.downcase }} that #{@p.added_labels.any? ? "uses #{@p.added_labels.join(', ').sub(/\A./) { |c| c.downcase }}" : 'changes the steps'}#{@p.removed_labels.any? ? " instead of #{@p.removed_labels.join(', ').sub(/\A./) { |c| c.downcase }}" : ''}.",
           "You did this skill differently #{@p.occurrences} times."]
        end
      std = SkillStandard.normalize(title: title.first(120), name: title, description: desc, body: "")
      Result.new(worthwhile: true, kind: @p.kind, confidence: [40 + 15 * @p.occurrences, 90].min, title: title.first(120),
                 description: std[:description], rationale: why, by: "rules")
    end
  end
end
