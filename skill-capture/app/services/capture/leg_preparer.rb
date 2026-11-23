require "anthropic"

module Capture
  # The AI preparer for one leg of the road: follows the leg's skill (its Agent Skills
  # instructions) over the confirmed figures, writes a short workpaper memo, and lists issues
  # (blocking ones stop verification until fixed or acknowledged). Rules write a plain memo.
  #
  # Claude sees the skill's instructions, the situation answers, the filing status and tax year,
  # and the documents as "W-2 #1: box1 85,000 ..." -- no names, payers or identifiers.
  class LegPreparer
    Result = Struct.new(:memo, :issues, :by, keyword_init: true)
    SEVERITIES = %w[blocking warning note].freeze

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are the preparer on a CPA team, working one leg of an individual income tax return. Follow the
      skill's instructions. You get the confirmed figures from the client's documents, the computed
      workpaper figures and the facts of the return. Write a short workpaper memo (markdown, at most 250
      words) saying what you did, the result and what the reviewer should look at. Then list issues:
      "blocking" only for something that would make the return wrong if filed as is (a missing document
      the facts call for, figures that can't both be right, a likely missed form); "warning" for things to
      confirm; "note" for context. Don't invent figures or year-specific limits; when one is needed, say
      which current IRS instruction to check. Never include names, SSNs or account numbers.
    PROMPT

    SCHEMA = {
      type: "object", additionalProperties: false, required: %w[memo issues],
      properties: {
        memo: { type: "string" },
        issues: { type: "array", items: { type: "object", additionalProperties: false, required: %w[severity text],
                                          properties: { severity: { type: "string", enum: SEVERITIES }, text: { type: "string" } } } }
      }
    }.freeze

    def self.call(run, leg, figures:, documents:, client: nil) = new(run, leg, figures, documents, client).call

    def initialize(run, leg, figures, documents, client)
      @run, @leg, @figures, @documents, @client = run, leg, figures, documents, client
      @skill = Skill.current(leg)
      @catalog = run.playbook.catalog
    end

    def call
      if @client || Config.llm_enabled?
        begin
          return claude
        rescue ClaudeDrafter::DraftError, Anthropic::Errors::Error, JSON::ParserError => e
          Rails.logger.warn("Leg #{@leg}: AI preparer fell back to rules: #{e.class}: #{e.message}")
        end
      end
      rules
    end

    private

    def fmt(v) = ActiveSupport::NumberHelper.number_to_delimited(v.to_f == v.to_f.round ? v.to_f.round : v.to_f.round(2))

    def doc_lines
      @documents.group_by(&:kind).flat_map do |kind, ds|
        ds.each_with_index.map do |d, i|
          figs = d.fields.map { |k, v| "#{k} #{v.is_a?(Numeric) ? fmt(v) : v}" }.join(", ")
          "#{@catalog.dig(kind, 'name') || 'Unidentified'} ##{i + 1} (#{d.status}#{d.tax_year ? ", #{d.tax_year}" : ''}): #{figs.presence || 'no figures'}"
        end
      end
    end

    def payload
      {
        leg: @skill&.title, instructions: @skill&.body,
        tax_year: @run.inputs["tax_year"], filing_status: @run.inputs["filing_status"],
        situations_that_apply: Situation.for_playbook(@run.playbook_key).select { |s| @run.applies?(s.key) }.map(&:question),
        documents: doc_lines, workpaper_figures: @figures,
        filer_inputs: @run.inputs.except("tax_year", "filing_status")
      }
    end

    def claude
      msg = (@client || Anthropic::Client.new).beta.messages.create(
        model: Config.llm_model, max_tokens: 8_000, system_: SYSTEM_PROMPT,
        output_config: { effort: :medium, format: { type: :json_schema, schema: SCHEMA } },
        fallbacks: :default, betas: ["server-side-fallback-2026-07-01"],
        messages: [{ role: "user", content: payload.to_json }]
      )
      raise ClaudeDrafter::DraftError, "model declined" if msg.stop_reason.to_s == "refusal"
      d = JSON.parse(msg.content.select { |b| b.type.to_s == "text" }.map(&:text).join)
      issues = Array(d["issues"]).filter_map do |i|
        sev = SEVERITIES.include?(i["severity"]) ? i["severity"] : "warning"
        text = i["text"].to_s.gsub(ReturnDocument::IDENTIFIER, "[removed]").squish.first(400)
        text.present? && { "severity" => sev, "text" => text }
      end
      Result.new(memo: d["memo"].to_s.gsub(ReturnDocument::IDENTIFIER, "[removed]").strip.first(4000), issues: issues.first(12), by: "ai")
    end

    def rules
      fig = @figures.map { |k, v| "- #{k.humanize}: #{fmt(v)}" }
      issues = []
      unconfirmed = @documents.reject { |d| d.status == "confirmed" }
      issues << { "severity" => "blocking", "text" => "#{unconfirmed.size} document(s) for this leg aren't confirmed yet." } if unconfirmed.any?
      memo = ["**#{@skill&.title}**", "",
              "Prepared from #{@documents.size} document(s)#{@documents.any? ? ": #{doc_lines.join('; ')}" : ''}.",
              *(fig.any? ? ["", "Workpaper figures:", *fig] : []), "",
              "Prepared by rules (no AI key): check each figure against the documents and the skill's instructions."].join("\n")
      Result.new(memo: memo, issues: issues, by: "rules")
    end
  end
end
