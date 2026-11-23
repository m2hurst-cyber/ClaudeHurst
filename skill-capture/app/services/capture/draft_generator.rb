module Capture
  # Fills in a candidate's draft: Claude when configured, the template otherwise
  # or when the Claude call fails for any reason.
  class DraftGenerator
    def self.call(candidate, **opts) = new(candidate, **opts).call

    def initialize(candidate, drafter: nil)
      @candidate = candidate
      @drafter = drafter
    end

    def call
      attrs, generator = generate
      # A person-recorded procedure keeps the title and description its author gave it.
      if @candidate.origin == "manual" && @candidate.draft_title.present?
        attrs = attrs.merge(title: @candidate.draft_title, name: Naming.skill_name(@candidate.draft_title))
        attrs[:description] = @candidate.draft_description if @candidate.draft_description.present?
      end
      @candidate.update!(
        draft_name: attrs[:name], draft_title: attrs[:title], draft_description: attrs[:description],
        draft_tags: attrs[:tags], draft_inputs: attrs[:inputs], draft_outputs: attrs[:outputs],
        draft_body: attrs[:body], draft_generator: generator, drafted_at: Time.current,
        status: @candidate.status == "detected" ? "drafted" : @candidate.status
      )
      AuditLog.record("skill_candidate.drafted", subject: @candidate, generator: generator)
      @candidate
    end

    private

    def generate
      return [@drafter.call(@candidate), "custom"] if @drafter
      if Config.llm_enabled?
        begin
          return [ClaudeDrafter.call(@candidate), "claude"]
        rescue ClaudeDrafter::DraftError, Anthropic::Errors::Error => e
          Rails.logger.warn("Capture: Claude draft failed for candidate ##{@candidate.id}; using template. #{e.class}: #{e.message}")
        end
      end
      [TemplateDrafter.call(@candidate), "template"]
    end
  end
end
