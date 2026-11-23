module Capture
  # Everything an AI needs to use a skill locally: the SKILL.md, its road and intersection
  # directions, and its resources (with download links). What the add-in stores in memory.
  module Bundle
    module_function

    # viewer: a User (their visibility) or nil (agents: firm/market only).
    # url_for: ->(resource) { download URL }
    def for(skill, viewer:, url_for:)
      directions = %W[road:#{skill.name} junction:#{skill.name}].filter_map do |k|
        p = Directions.find(k, viewer: viewer)
        { key: p.key, kind: p.kind, title: p.title, written: p.written, markdown: p.body }
      rescue Directions::NotFound
        nil
      end
      c = SkillClassification.includes(field_assignments: :field).find_by(skill_name: skill.name)
      {
        name: skill.name, version: skill.version, title: skill.title, description: skill.description,
        stage: skill.stage, area: skill.domain, fields: c ? c.ordered_fields.map(&:label) : [], apps: c&.apps || [],
        skill_md: skill.to_skill_md, directions: directions,
        resources: ResourceLibrary.for_skill(skill.name, viewer.nil? ? nil : viewer).map { |r| ResourceLibrary.describe(r, download_url: url_for.(r)) }
      }
    end

    # Ordered bundles for a list of skill names, skipping any the viewer can't see.
    def for_names(names, viewer:, url_for:)
      names.filter_map do |n|
        s = Skill.current(n)
        next unless s && (viewer.nil? ? s.shared? : s.visible_to?(viewer))
        self.for(s, viewer: viewer, url_for: url_for)
      end
    end
  end
end
