module Capture
  # The files a personal backup writes: one SKILL.md per skill, a manifest that pins each
  # by content hash, and a README saying what this is and what it is not.
  #
  # The manifest is the useful part. A folder of Markdown is a copy; a folder of Markdown
  # with the hashes that produced it can be checked against the system it came from, which
  # is what makes it a backup rather than a pile.
  module GitExport
    module_function

    def files(backup)
      skills = backup.skills.to_a
      prefix = backup.path_prefix.presence&.then { |p| "#{p.delete_suffix('/')}/" } || ""
      out = skills.to_h { |s| ["#{prefix}#{s.name}.md", s.to_skill_md] }
      out["#{prefix}manifest.json"] = JSON.pretty_generate(manifest(backup, skills))
      out["#{prefix}README.md"] = readme(backup, skills)
      out
    end

    def manifest(backup, skills)
      {
        "generated_at" => Time.current.utc.iso8601,
        "source" => "Skill Capture",
        "scope" => GitBackup.own_work_only? ? "the skills this person wrote or contributed to" : "every skill this person can see",
        "skills" => skills.map do |s|
          { "name" => s.name, "version" => s.version, "title" => s.title, "stage" => s.stage,
            "content_hash" => s.content_hash, "licence" => s.license, "file" => "#{s.name}.md" }
        end
      }
    end

    def readme(backup, skills)
      <<~MD
        # Skills — #{backup.user.name}

        #{skills.size} #{'skill'.pluralize(skills.size)}, exported from Skill Capture on #{Time.current.utc.strftime('%-d %B %Y')}.
        Each file is an Agent Skills `SKILL.md`: a procedure a colleague or an AI agent can follow.

        `manifest.json` pins every file to the content hash it had in the system it came from.
        That hash covers the skill's name, title, description, body, tags, inputs, outputs,
        workflow and licence — so this copy can be checked against the original, by anyone,
        without access to that system.

        ## What this is not

        This is a copy for safekeeping, not the source of truth. Editing a file here changes
        nothing in Skill Capture, and the next backup will overwrite it.

        ## Licence

        #{skills.map(&:license).uniq.sort.join("\n")}

        Check these before sharing this repository. Skills carrying an internal or proprietary
        licence are your employer's, not yours, whatever account this repository sits in.
      MD
    end

    def commit_message(skills_count)
      "Skill Capture backup: #{skills_count} #{'skill'.pluralize(skills_count)} as at #{Time.current.utc.strftime('%Y-%m-%d %H:%M UTC')}"
    end
  end
end
