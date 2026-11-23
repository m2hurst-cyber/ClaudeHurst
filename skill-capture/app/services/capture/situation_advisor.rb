require "anthropic"

module Capture
  # Acts like the CPA when a preparer describes something the questionnaire didn't ask about:
  # is it one of the playbook's known situations, or a new one? For a new one it proposes
  # where it leaves the mainline, the intake question, the forms, a few steps, and a title
  # and description in the Agent Skills format. That proposal becomes a branch candidate.
  #
  # Claude when configured; otherwise keyword rules. Only the redacted description and the
  # playbook's own structure are sent: digits runs (SSNs, EINs, account numbers, amounts) and
  # email addresses are removed first.
  class SituationAdvisor
    Result = Struct.new(:match, :proposal, :rationale, :by, keyword_init: true)

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You are a CPA supervising individual income tax returns. A preparer describes something about a
      client's year. Decide whether it is one of the listed situations (match_key) or a new one
      (match_key "none"). For a new situation, choose the mainline step it should branch from
      (after_step: the step whose work it extends), write the yes/no intake question a preparer would ask
      every client, list the IRS forms or schedules involved, 2-4 short imperative steps, search keywords,
      and a title and description in Anthropic's Agent Skills format (description in the third person,
      says what it does and when to use it, under 1024 characters). Be conservative: prefer an existing
      situation when it reasonably covers the description. Don't give year-specific dollar limits.
    PROMPT

    def self.call(playbook, text, client: nil) = new(playbook, text, client: client).call

    def self.redact(text)
      text.to_s.gsub(/\S+@\S+/, "[email]").gsub(/\d[\d,.\-\/]{2,}/, "#").squish.first(500)
    end

    def initialize(playbook, text, client: nil)
      @pb = playbook
      @text = self.class.redact(text)
      @client = client
      @situations = Situation.for_playbook(@pb.key).to_a
    end

    def call
      if @client || Config.llm_enabled?
        begin
          return claude
        rescue ClaudeDrafter::DraftError, Anthropic::Errors::Error, JSON::ParserError, KeyError => e
          Rails.logger.warn("Situation advisor fell back to rules: #{e.class}: #{e.message}")
        end
      end
      rules
    end

    private

    def schema
      { type: "object", additionalProperties: false,
        required: %w[match_key after_step question title description forms steps keywords rationale],
        properties: {
          match_key: { type: "string", enum: @situations.map(&:key) + ["none"] },
          after_step: { type: "string", enum: @pb.mainline_names },
          question: { type: "string" }, title: { type: "string" }, description: { type: "string" },
          forms: { type: "array", items: { type: "string" } }, steps: { type: "array", items: { type: "string" } },
          keywords: { type: "array", items: { type: "string" } }, rationale: { type: "string" }
        } }
    end

    def claude
      payload = {
        description: @text,
        mainline: @pb.mainline.map { |m| { step: m["name"], title: @pb.skill_spec(m["name"])["title"] } },
        situations: @situations.map { |s| { key: s.key, question: s.question, forms: s.forms, after_step: s.after_skill } }
      }
      msg = (@client || Anthropic::Client.new).beta.messages.create(
        model: Config.llm_model, max_tokens: 4_000, system_: SYSTEM_PROMPT,
        output_config: { effort: :low, format: { type: :json_schema, schema: schema } },
        fallbacks: :default, betas: ["server-side-fallback-2026-07-01"],
        messages: [{ role: "user", content: payload.to_json }]
      )
      raise ClaudeDrafter::DraftError, "model declined" if msg.stop_reason.to_s == "refusal"
      d = JSON.parse(msg.content.select { |b| b.type.to_s == "text" }.map(&:text).join)
      match = @situations.find { |s| s.key == d["match_key"] }
      return Result.new(match: match, rationale: d["rationale"].to_s.squish, by: "ai") if match
      after = @pb.mainline_names.include?(d.fetch("after_step")) ? d["after_step"] : guess_after
      Result.new(match: nil, by: "ai", rationale: d["rationale"].to_s.squish,
                 proposal: { after: after, question: d["question"].to_s.squish, title: d["title"].to_s.squish.first(120),
                             description: d["description"].to_s.squish, forms: Array(d["forms"]).map(&:to_s).first(8),
                             steps: Array(d["steps"]).map { |x| x.to_s.squish.first(120) }.reject(&:blank?).first(4),
                             keywords: Array(d["keywords"]).map { |x| x.to_s.downcase.squish }.first(12) })
    end

    def rules
      words = @text.downcase
      best = @situations.map { |s| [s, s.keywords.count { |k| words.include?(k.downcase) }] }.max_by(&:last)
      return Result.new(match: best[0], rationale: "Matches the #{best[0].key.tr('-', ' ')} situation's keywords.", by: "rules") if best && best[1].positive?

      what = @text.sub(/[.\s]+\z/, "").sub(/\A(my |our |the )?(client|taxpayer)s?\s+/i, "")
      title = "Handle: client #{what.sub(/\A./) { |c| c.downcase }}".first(90)
      Result.new(match: nil, by: "rules", rationale: "No existing situation covers this; proposed as a new branch for review.",
                 proposal: { after: guess_after, question: "Did this happen: the client #{what.sub(/\A./) { |c| c.downcase }}?",
                             title: title, forms: [],
                             description: "Handles a situation the standard route doesn't cover: #{what.sub(/\A./) { |c| c.downcase }}. Use when a client's return involves it.",
                             steps: ["Gather the documents for this situation", "Determine the tax treatment and forms", "Enter it in the return and document the support"],
                             keywords: what.downcase.scan(/[a-z0-9-]{4,}/).uniq.first(8) })
    end

    def guess_after
      t = @text.downcase
      names = @pb.mainline_names
      pick = if t.match?(/\b(deduct|credit|donat|charit|medical|child|care\b|tuition|insurance|contribut|mortgage)/) then names.find { |n| n.include?("deduction") }
             elsif t.match?(/\b(states?|foreign|countr|abroad|overseas)/) then names.find { |n| n.include?("prepare") }
             elsif t.match?(/\b(pay|owes?|owed|notices?|penalt|levy|liens?)\b/) then names.find { |n| n.start_with?("pay") }
             else names.find { |n| n.include?("income") }
             end
      pick || names[names.size / 2]
    end
  end
end
