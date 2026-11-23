require "anthropic"

module Capture
  # Reads an uploaded tax document: identifies its kind from the playbook's catalog and copies out
  # the boxes the preparer uses. Claude reads the PDF or image directly (structured output); the
  # filer then checks the figures against the document and confirms them. Without an AI key, or
  # when the admin turns AI reading off, the filer chooses the kind and types the boxes.
  #
  # Identifiers are never copied out: the schema has no field for them, Claude is told not to, and
  # anything that still looks like an SSN, EIN or account number is stripped before it's stored.
  class DocumentReader
    class Error < StandardError; end
    Result = Struct.new(:kind, :tax_year, :payer, :fields, :confidence, :notes, keyword_init: true)

    SYSTEM_PROMPT = <<~PROMPT.freeze
      You read US individual income tax documents for a CPA's workpapers. Identify which catalog kind the
      document is (or "other"), its tax year, the payer or issuer's business name, and copy the listed
      boxes exactly as printed (numbers only for amounts, no $ or commas; leave out boxes that are blank).
      Never copy Social Security numbers, ITINs, EINs, account numbers, addresses or the taxpayer's name:
      there are no fields for them and they must not appear anywhere in your answer, including notes.
      If the document is unreadable, a different tax year than printed elsewhere, marked CORRECTED, or a
      VOID copy, say so in notes. Give a confidence from 0 to 100 for the figures.
    PROMPT

    def self.enabled? = Config.llm_enabled? && ENV["SKILL_CAPTURE_AI_DOCUMENTS"] != "off"

    def self.call(doc, client: nil) = new(doc, client: client).call

    def initialize(doc, client: nil)
      @doc = doc
      @catalog = doc.playbook_run.playbook.catalog
      @client = client
    end

    def call
      msg = (@client || Anthropic::Client.new).beta.messages.create(
        model: Config.llm_model, max_tokens: 4_000, system_: SYSTEM_PROMPT,
        output_config: { effort: :low, format: { type: :json_schema, schema: schema } },
        fallbacks: :default, betas: ["server-side-fallback-2026-07-01"],
        messages: [{ role: "user", content: [source_block, { type: "text", text: "Catalog:\n#{catalog_text}" }] }]
      )
      raise Error, "the model declined to read this document" if msg.stop_reason.to_s == "refusal"
      raise Error, "the answer was cut off" if msg.stop_reason.to_s == "max_tokens"
      d = JSON.parse(msg.content.select { |b| b.type.to_s == "text" }.map(&:text).join)
      kind = @catalog.key?(d["kind"]) ? d["kind"] : "other"
      Result.new(kind: kind, tax_year: d["tax_year"].to_i.nonzero?, payer: scrub(d["payer"]).first(80),
                 fields: Array(d["fields"]).to_h { |f| [f["key"].to_s, f["value"]] }, confidence: d["confidence"].to_i.clamp(0, 100),
                 notes: scrub(d["notes"]).first(500))
    rescue JSON::ParserError => e
      raise Error, "unreadable answer: #{e.message}"
    end

    private

    def source_block
      data = Base64.strict_encode64(@doc.bytes)
      if @doc.content_type == "application/pdf"
        { type: "document", source: { type: "base64", media_type: "application/pdf", data: data } }
      else
        { type: "image", source: { type: "base64", media_type: @doc.content_type, data: data } }
      end
    end

    def catalog_text
      @catalog.map { |k, v| "#{k}: #{v['name']} -- #{Array(v['fields']).map { |f| "#{f['key']} (#{f['label']}, #{f['type']})" }.join('; ')}" }.join("\n")
    end

    def schema
      keys = @catalog.values.flat_map { |v| Array(v["fields"]).map { |f| f["key"] } }.uniq
      { type: "object", additionalProperties: false, required: %w[kind tax_year payer fields confidence notes],
        properties: {
          kind: { type: "string", enum: @catalog.keys.map(&:to_s) | ["other"] },
          tax_year: { type: "integer" }, payer: { type: "string" },
          fields: { type: "array", items: { type: "object", additionalProperties: false, required: %w[key value],
                                            properties: { key: { type: "string", enum: keys }, value: { type: "string" } } } },
          confidence: { type: "integer" }, notes: { type: "string" }
        } }
    end

    def scrub(s) = s.to_s.gsub(ReturnDocument::IDENTIFIER, "[removed]").squish
  end
end
