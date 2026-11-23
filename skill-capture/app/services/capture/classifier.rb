require "anthropic"

module Capture
  # Infers a skill's field (from the taxonomy) and the apps it uses.
  #
  #   Apps   observed from the skill's steps (excel.*, word.*, ...) plus apps named in its text
  #   Field  Claude, given the taxonomy as a closed list (structured output), when configured;
  #          otherwise keyword rules over title, description and step labels
  # Results never overwrite a classification a person set or confirmed.
  class Classifier
    APP_PREFIXES = { "excel" => "Excel", "word" => "Word", "powerpoint" => "PowerPoint", "outlook" => "Outlook",
                     "teams" => "Teams", "powerbi" => "Power BI", "bi" => "Power BI", "sharepoint" => "SharePoint" }.freeze
    APP_WORDS = { /\boutlook\b|\bemail\b/i => "Outlook", /\bteams\b/i => "Teams", /power ?bi/i => "Power BI", /sharepoint/i => "SharePoint" }.freeze

    MAX_FIELDS = 3
    Result = Struct.new(:fields, :apps, :source, :confidence, :rationale, keyword_init: true) do
      def field = fields.first
    end

    def self.call(skill, client: nil) = new(skill, client: client).call

    # Infer and store, unless a person has set or confirmed it (then only observed apps are merged in).
    def self.apply!(skill, client: nil)
      Taxonomy.ensure_defaults!
      c = SkillClassification.find_or_initialize_by(skill_name: skill.name)
      if c.confirmed
        c.update!(apps: c.apps | observed_apps(skill))
        return c
      end
      r = call(skill, client: client)
      c.update!(apps: r.apps, source: r.source, confidence: r.confidence, rationale: r.rationale, inferred_at: Time.current)
      c.set_fields!(r.fields, source: r.source)
    end

    def self.observed_apps(skill)
      Array(skill.source["workflow"]).filter_map { |k| APP_PREFIXES[k.to_s.split(/[.:]/).first] }.uniq
    end

    def initialize(skill, client: nil)
      @skill = skill
      @client = client
    end

    def call
      observed = self.class.observed_apps(@skill)
      if Config.llm_enabled? || @client
        begin
          return claude(observed)
        rescue ClaudeDrafter::DraftError, Anthropic::Errors::Error, JSON::ParserError => e
          Rails.logger.warn("Classifier: Claude failed for #{@skill.name}; using rules. #{e.class}: #{e.message}")
        end
      end
      rules(observed)
    end

    private

    def labels = ActionDefinition.labels_for(Array(@skill.source["workflow"])).values

    def text_apps
      text = [@skill.title, @skill.description, *labels].join(" ")
      APP_WORDS.filter_map { |re, app| app if text.match?(re) }
    end

    def rules(observed)
      fields = Field.all.to_a
      title = @skill.title.to_s.downcase
      rest = [@skill.description, *labels, @skill.tags.join(" ")].join(" ").downcase
      own = fields.to_h do |f|
        hits = f.keywords.select { |k| title.include?(k) || rest.include?(k) }
        score = f.keywords.sum { |k| (title.include?(k) ? 2 : 0) + (rest.include?(k) ? 1 : 0) }
        score += 1 if f.parent_id.nil? && @skill.domain.present? && f.slug == @skill.domain.to_s.parameterize
        [f.id, [score, hits]]
      end
      by_id = fields.index_by(&:id)
      # A node's evidence includes its ancestors' (a "Reconciliation" match inside "Finance" beats a stray hit elsewhere).
      total = ->(f) { f.ancestors_and_self.sum { |a| own[a.id][0] } }
      ranked = fields.select { |f| own[f.id][0].positive? }.sort_by { |f| [-total.(f), -f.depth] }
      best = ranked.first
      apps = (observed | text_apps)
      return Result.new(fields: [], apps: apps, source: "rules", confidence: nil, rationale: "No keywords matched the taxonomy.") unless best
      # Also keep other strong matches (at least 60% of the best), skipping ancestors/descendants of ones kept.
      chosen = []
      ranked.each do |f|
        break if chosen.size >= MAX_FIELDS
        next if total.(f) < [total.(best) * 0.6, 2].max
        next if chosen.any? { |c| f.path.start_with?("#{c.path}/") || c.path.start_with?("#{f.path}/") }
        chosen << f
      end
      hits = chosen.flat_map { |f| f.ancestors_and_self.flat_map { |a| own[a.id][1] } }.uniq
      Result.new(fields: chosen, apps: apps, source: "rules", confidence: [0.35 + 0.08 * total.(best), 0.85].min.round(2),
                 rationale: "Matched #{hits.first(5).map { |h| "“#{h}”" }.join(', ')}#{" and its area (#{@skill.domain})" if @skill.domain.present? && by_id.values.any? { |f| f.slug == @skill.domain.to_s.parameterize }}.")
    end

    SYSTEM = <<~PROMPT.freeze
      You classify an organization's reusable work procedures ("skills").
      Pick the most specific fields from the taxonomy that describe the kind of work (one to three,
      most important first; more than one only when the procedure genuinely spans them), and
      the Microsoft apps the procedure uses. Choose only from the lists given. If nothing fits, return no fields.
      Give a confidence from 0 to 1 and a one-sentence rationale a colleague would find convincing.
    PROMPT

    def claude(observed)
      fields = Field.all.to_a
      schema = {
        type: "object", additionalProperties: false, required: %w[field_paths apps confidence rationale],
        properties: {
          field_paths: { type: "array", items: { type: "string", enum: fields.map(&:path) } },
          apps: { type: "array", items: { type: "string", enum: SkillClassification::APPS } },
          confidence: { type: "number" },
          rationale: { type: "string" }
        }
      }
      payload = {
        skill: { title: @skill.title, description: @skill.description, area: @skill.domain, steps: labels, apps_seen_in_steps: observed },
        taxonomy: fields.sort_by(&:path).map { |f| { path: f.path, label: f.label } }
      }
      client = @client || Anthropic::Client.new
      msg = client.beta.messages.create(
        model: Config.llm_model, max_tokens: 2_000, system_: SYSTEM,
        output_config: { effort: :low, format: { type: :json_schema, schema: schema } },
        fallbacks: :default, betas: ["server-side-fallback-2026-07-01"],
        messages: [{ role: "user", content: payload.to_json }]
      )
      raise ClaudeDrafter::DraftError, "declined" if msg.stop_reason.to_s == "refusal"
      d = JSON.parse(msg.content.select { |b| b.type.to_s == "text" }.map(&:text).join)
      chosen = Array(d["field_paths"]).uniq.filter_map { |p| fields.find { |f| f.path == p } }.first(MAX_FIELDS)
      Result.new(fields: chosen, apps: observed | (Array(d["apps"]) & SkillClassification::APPS), source: "ai",
                 confidence: d["confidence"].to_f.clamp(0, 1).round(2), rationale: d["rationale"].to_s.first(500))
    end
  end
end
