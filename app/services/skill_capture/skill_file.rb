module SkillCapture
  # Serializes a Skill as an Agent Skills SKILL.md (YAML frontmatter + Markdown body)
  # and writes it to the skill repository directory.
  module SkillFile
    module_function

    def render(skill)
      front = {
        "name" => skill.name,
        "description" => skill.description,
        "license" => skill.license,
        "metadata" => {
          "title" => skill.title,
          "version" => skill.version.to_s,
          "domain" => skill.domain,
          "tags" => skill.tags,
          "inputs" => skill.inputs,
          "outputs" => skill.outputs,
          "status" => skill.status,
          "parent" => skill.parent_skill && "#{skill.parent_skill.name}@#{skill.parent_skill.version}",
          "published_at" => skill.published_at&.iso8601,
          "published_by" => skill.published_by&.display_name,
          "source" => skill.source.except("contributor_ids")
        }.compact
      }
      "#{front.to_yaml}---\n\n#{skill.body.strip}\n"
    end

    def export_dir
      dir = ENV["SKILL_CAPTURE_EXPORT_DIR"]
      dir.present? ? Pathname.new(dir) : nil
    end

    # Writes <dir>/<name>/SKILL.md. Returns the path, or nil when export is not configured.
    def export(skill, dir: export_dir)
      return nil unless dir
      path = Pathname.new(dir).join(skill.name, "SKILL.md")
      FileUtils.mkdir_p(path.dirname)
      File.write(path, render(skill))
      path
    end
  end
end
