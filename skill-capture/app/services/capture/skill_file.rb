module Capture
  # Agent Skills SKILL.md: YAML frontmatter (name, description, license, metadata) + Markdown body.
  module SkillFile
    module_function

    # Frontmatter per the Agent Skills format: name and description (required), license, and
    # metadata as a flat map of strings. Provenance stays in the console and the API, not here.
    def render(skill)
      src = skill.source
      metadata = {
        "title" => skill.title,
        "version" => skill.version.to_s,
        "area" => skill.domain,
        "stage" => skill.stage,
        "tags" => skill.tags.presence&.join(", "),
        "inputs" => skill.inputs.presence&.join("; "),
        "outputs" => skill.outputs.presence&.join("; "),
        "parent" => skill.parent_skill && "#{skill.parent_skill.name}@#{skill.parent_skill.version}",
        "published-at" => skill.published_at&.iso8601,
        "published-by" => skill.published_by&.name,
        "captured-from" => src["occurrences"] && "#{src['occurrences']} runs by #{src['distinct_people'] || 1} people"
      }.compact.transform_values(&:to_s)
      front = { "name" => skill.name, "description" => skill.description, "license" => skill.license, "metadata" => metadata }
      "#{front.to_yaml}---\n\n#{skill.body.strip}\n"
    end

    def export_dir
      dir = ENV["SKILL_CAPTURE_EXPORT_DIR"]
      dir.present? ? Pathname.new(dir) : nil
    end

    # Writes <dir>/<name>/SKILL.md (the current version). Returns the path, or nil if export is off.
    def export(skill, dir: export_dir)
      return nil unless dir
      path = Pathname.new(dir).join(skill.name, "SKILL.md")
      FileUtils.mkdir_p(path.dirname)
      File.write(path, render(skill))
      path
    end
  end
end
