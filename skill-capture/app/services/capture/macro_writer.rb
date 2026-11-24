require "anthropic"

module Capture
  # The AI writes the macro the first time it does the task.
  #
  # A task screened as scriptable still runs on the AI once: the AI does the work and, from what it
  # just did, writes the script that will do it next time. The script goes to the review queue marked
  # "written by the AI from the first run". Once a person approves it, later runs skip the AI entirely.
  #
  # An agent that knows exactly what it did can hand the script over itself, by posting `macro` with its
  # run; this is the fallback when it doesn't.
  class MacroWriter
    class Error < StandardError; end

    SYSTEM = <<~TXT
      You write small, deterministic Office macros that replace an AI call with a script.

      You are given a task that an AI has just finished, with the instructions it followed and the note
      it left about what it did. Write the script that would do that same task again, unattended, on a
      different workbook or document of the same shape.

      Rules:
      - Write only what repeats. If part of the task needed judgment (choosing, writing prose, reading
        meaning into numbers), leave it out and say so in `leaves_to_ai`.
      - For Excel, write an add-in script: one `async function run(context)` using the Office.js Excel
        API (context.workbook…, load(), await context.sync()), returning a short line saying what it did.
      - For Word or PowerPoint, write VBA: one Sub, no user interaction, no MsgBox.
      - Never invent file paths, sheet names or ranges that the instructions don't mention; read what is
        there (used ranges, named items) instead of hard-coding.
      - No credentials, no network calls, no deleting files, no changes outside the open document.
      - If the task can't be scripted honestly, return confidence "none" and an empty script.
    TXT

    SCHEMA = {
      type: "object", additionalProperties: false,
      required: %w[language code steps confidence leaves_to_ai caveats],
      properties: {
        language: { type: "string", enum: %w[addin_js vba none] },
        code: { type: "string" },
        steps: { type: "array", items: { type: "string" } },
        confidence: { type: "string", enum: %w[high medium low none] },
        leaves_to_ai: { type: "array", items: { type: "string" } },
        caveats: { type: "array", items: { type: "string" } }
      }
    }.freeze

    def self.call(**kw) = new(**kw).call

    def initialize(title:, instructions: nil, app: "Excel", skill: nil, note: nil, usage: nil, client: nil)
      @title = title.to_s
      @instructions = instructions
      @app = app.presence || "Excel"
      @skill = skill
      @note = note
      @usage = usage
      @client = client
    end

    # Returns the suggestion hash for a MacroReview, or nil when there's nothing worth proposing.
    def call
      return nil unless @client || Config.llm_enabled?
      msg = (@client || Anthropic::Client.new).beta.messages.create(
        model: Config.llm_model, max_tokens: 8_000, system_: SYSTEM,
        output_config: { effort: :medium, format: { type: :json_schema, schema: SCHEMA } },
        fallbacks: :default, betas: ["server-side-fallback-2026-07-01"],
        messages: [{ role: "user", content: payload.to_json }]
      )
      raise Error, "declined" if msg.stop_reason.to_s == "refusal"
      parse(JSON.parse(msg.content.select { |b| b.type.to_s == "text" }.map(&:text).join))
    rescue Error, Anthropic::Errors::Error, JSON::ParserError => e
      Rails.logger.warn("MacroWriter: #{e.class}: #{e.message}")
      nil
    end

    private

    def payload
      { app: @app, task: @title, instructions: @instructions, skill: @skill&.body&.truncate(4_000),
        what_the_ai_did: @note, tokens_it_cost: @usage && (@usage["input_tokens"].to_i + @usage["output_tokens"].to_i) }.compact
    end

    def parse(d)
      return nil if d["language"] == "none" || d["confidence"] == "none" || d["code"].to_s.strip.length < 20
      lang = d["language"].presence_in(MacroReview::LANGUAGES) || (@app == "Excel" ? "addin_js" : "vba")
      return nil if lang == "addin_js" && !d["code"].match?(MacroReview::DEFINES_RUN)
      { "language" => lang, "code" => d["code"].to_s.strip, "steps" => Array(d["steps"]).map(&:to_s).first(12),
        "confidence" => d["confidence"], "leaves_to_ai" => Array(d["leaves_to_ai"]).map(&:to_s).first(6),
        "caveats" => Array(d["caveats"]).map(&:to_s).first(6) }
    end
  end
end
