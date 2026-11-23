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
      attrs = attrs.merge(name: proposed_name(attrs[:name])) if @candidate.base_skill
      attrs = SkillStandard.normalize(attrs) # Anthropic Agent Skills format, whichever drafter wrote it
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

    # Extending keeps the skill's name (it publishes as the next version); a branch gets its own.
    def proposed_name(drafted)
      base = @candidate.base_skill
      return base.name if @candidate.proposal_kind == "extend"
      name = drafted.presence && drafted != base.name ? drafted : "#{base.name}-variant"
      name = Naming.skill_name(name)
      candidate = name
      n = 2
      while Skill.exists?(name: candidate) || SkillCandidate.open.where.not(id: @candidate.id).exists?(draft_name: candidate)
        candidate = Naming.skill_name("#{name.first(60)}-#{n}")
        n += 1
      end
      candidate
    end

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
