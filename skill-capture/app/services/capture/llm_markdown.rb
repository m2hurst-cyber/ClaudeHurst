module Capture
  # Markdown for LLMs and agents: everything an assistant needs about a skill, a flow, a run, a captured
  # worksheet or a formula library, as one .md document ("Copy for LLM", "View as Markdown", `.md` URLs).
  module LlmMarkdown
    module_function

    def h = Rails.application.routes.url_helpers
    def cell(v) = v.to_s.gsub("|", "\\|").gsub(/\s*\n\s*/, " ")

    # The skill's SKILL.md, then its road directions, the next turn, resources, worksheet formulas and AI usage.
    def skill(s, viewer: nil)
      out = [s.to_skill_md.strip, ""]
      %W[road:#{s.name} junction:#{s.name}].each do |k|
        p = Directions.find(k, viewer: viewer)
        out += ["## #{p.title}", "", p.body.to_s.strip, ""] if p.written && p.body.present?
      rescue Directions::NotFound
        nil
      end
      res = ResourceLibrary.for_skill(s.name, viewer)
      if res.any?
        out += ["## Resources", ""] + res.map { |r| "- #{r.name} (`#{r.key}`)" } + [""]
      end
      if (u = Intensity.for(s.name))
        out += ["## AI usage (last 90 days)", "",
                "#{u[:runs]} runs · #{u[:avg_tokens]} tokens per run (#{u[:avg_input_tokens]} in, #{u[:avg_output_tokens]} out)#{u[:avg_seconds] ? " · #{u[:avg_seconds]} s per run" : ''}#{u[:intensity] ? " · #{u[:intensity]} intensity" : ''}", ""]
      end
      out += ["---", "", "Report each run of this skill: `POST #{h.api_v1_skill_runs_path(s.name)}` with `model`, `input_tokens`, `output_tokens`, `duration_ms`."]
      out.join("\n")
    end

    def flow(f)
      out = ["# #{f.name}", ""]
      out += [f.description, ""] if f.description.present?
      out += ["A flow: tasks run in order; when one is done it hands off to the next, in the app (lane) and to the person or agent named.", "",
              "| # | Task | Where | Who | Skill | Instructions |", "|---|---|---|---|---|---|"]
      f.steps.each_with_index do |s, i|
        if Flow.pause?(s)
          out << "| ⏸ | #{cell(s['title'])} | — | — | — | #{cell(Flow.pause_label(s))}#{s['instructions'] ? ": #{cell(s['instructions'])}" : ''} |"
        else
          out << "| #{i + 1} | #{cell(s['title'])} | #{s['app']} | #{cell(Flow.assignee_label(s['assignee'], owner: f.user))} | #{s['skill_name'] ? "`#{s['skill_name']}`" : ''} | #{cell(s['instructions'])} |"
        end
      end
      out.join("\n")
    end

    def run(r)
      cur = r.current
      out = ["# #{r.flow.name}: run", "",
             "Started by #{r.user.name} on #{r.created_at.to_fs(:long)} · status: **#{r.status.humanize.downcase}** · #{r.done_count} of #{r.steps.size} done", ""]
      out += ["**Now:** #{Flow.pause?(cur) ? "paused (#{Flow.pause_label(cur)})" : "task #{r.current_index + 1}, #{cur['title']} (#{Flow.assignee_label(cur['assignee'], owner: r.user)}, #{cur['app']})"}", ""] if r.active? && cur
      out += ["| # | Task | Where | Who | State | Result |", "|---|---|---|---|---|---|"]
      r.steps.each_with_index do |s, i|
        u = s["usage"] ? " (#{s.dig('usage', 'model')}, #{s.dig('usage', 'input_tokens').to_i + s.dig('usage', 'output_tokens').to_i} tokens)" : ""
        out << "| #{Flow.pause?(s) ? '⏸' : i + 1} | #{cell(s['title'])} | #{Flow.pause?(s) ? '—' : s['app']} | #{Flow.pause?(s) ? cell(Flow.pause_label(s)) : cell(Flow.assignee_label(s['assignee'], owner: r.user))} | #{i == r.current_index && r.active? ? "**#{s['state']} (now)**" : s['state']} | #{cell([s['by'], s['note']].compact.join(': '))}#{cell(u)} |"
      end
      out.join("\n")
    end

    def capture(c)
      ["# Captured worksheet: #{c.interpretation['title'].presence || c.sheet_name}", "",
       "Sheet “#{c.sheet_name}” · #{FormulaCommand.provider_name(c.provider)} · captured by #{c.user.name} · interpreted by #{c.interpreted_by}", "",
       c.skill_md.to_s.strip, "", "---", "", c.structure_md.to_s.strip, "", "---", "", c.formulas_md.to_s.strip, "", "---", "",
       "## blueprint.json", "", "```json", JSON.pretty_generate(c.blueprint), "```"].join("\n")
    end

    def formulas(provider, commands)
      out = ["# #{FormulaCommand.provider_name(provider)} formula library", "",
             "Commands worksheet skills are built from. `{param}` placeholders are filled in when a sheet is built; unverified commands need checking against #{FormulaCommand.provider_name(provider)}.", ""]
      commands.group_by(&:category).sort_by { |k, _| k.to_s }.each do |cat, list|
        out += ["## #{cat.presence || 'Other'}", "", "| Key | Name | Syntax | Defaults | Status | Notes |", "|---|---|---|---|---|---|"]
        list.each { |c| out << "| `#{c.key}` | #{cell(c.name)} | `#{cell(c.syntax)}` | #{cell(c.params.filter_map { |k| "#{k}=#{c.defaults[k]}" if c.defaults.key?(k) }.join(', '))} | #{c.status} | #{cell(c.description)} |" }
        out << ""
      end
      out.join("\n")
    end

    def transfer(t)
      ["# Skill transfer: #{t.label}", "", "#{t.sender.name} → #{t.recipient.name} · #{t.free? ? 'free' : "#{t.price.to_s('F')} credits"} · #{t.state_word}", "",
       "Terms hash: `#{t.terms_hash}` · log #{t.log_intact? ? 'intact' : 'BROKEN'}", "",
       "| Skill | Version | Fingerprint |", "|---|---|---|", *t.items.map { |i| "| #{cell(i['title'])} (`#{i['name']}`) | v#{i['version']} | `#{i['sha256'].to_s.first(16)}` |" }, "",
       "## Contract log", "", *t.contract_log.map { |e| "#{e['seq']}. **#{e['event'].humanize}** · #{e['at']}#{e['by'] ? " · #{e['by']}" : ''} · `#{e['hash'].first(12)}`" }].join("\n")
    end
  end
end
