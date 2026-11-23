module SkillCapture
  # Produces (or refreshes) the draft on a candidate: Claude when configured,
  # the deterministic template otherwise or when the LLM call fails.
  class DraftGenerator
    def self.call(candidate, **opts) = new(candidate, **opts).call

    def initialize(candidate, drafter: nil)
      @candidate = candidate
      @drafter = drafter
    end

    def call
      attrs, generator = generate
      @candidate.update!(
        draft_name: attrs[:name],
        draft_title: attrs[:title],
        draft_description: attrs[:description],
        draft_tags: attrs[:tags],
        draft_inputs: attrs[:inputs],
        draft_outputs: attrs[:outputs],
        draft_body: attrs[:body],
        draft_generator: generator,
        drafted_at: Time.current,
        status: @candidate.status == "detected" ? "drafted" : @candidate.status
      )
      AuditLogger.record(user: nil, action: "skill_candidate.drafted", subject: @candidate, metadata: { generator: generator })
      @candidate
    end

    private

    def generate
      return [@drafter.call(@candidate), "custom"] if @drafter
      if Config.llm_enabled?
        begin
          return [ClaudeDrafter.call(@candidate), "claude"]
        rescue ClaudeDrafter::DraftError, Anthropic::Errors::APIError => e
          Rails.logger.warn("SkillCapture: Claude draft failed for candidate ##{@candidate.id}, using template: #{e.class}: #{e.message}")
        end
      end
      [TemplateDrafter.call(@candidate), "template"]
    end
  end
end
