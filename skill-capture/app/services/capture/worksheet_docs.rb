module Capture
  # Documents a worksheet blueprint: its pieces (every formula, with the command it comes from and
  # what it returns) and its structures (blocks, inputs, columns, dependencies). Used for captured
  # worksheets (STRUCTURE.md, FORMULAS.md) and for each worksheet skill's agent directions.
  module WorksheetDocs
    module_function

    def provider_name(p) = FormulaCommand.provider_name(p.to_s.presence || "excel")

    # One entry per formula pattern in the blueprint.
    def inventory(bp, commands)
      bp = bp.to_h
      kind = bp["kind"] || "table"
      inputs = Array(bp["inputs"]).to_h { |i| [i["key"], i["label"] || i["key"].humanize] }
      out = []
      case kind
      when "table"
        cols = Array(bp["columns"])
        varying = cols.flat_map { |c| c["params"].to_h.keys }.uniq
        Array(bp["rows"]).each do |r|
          out << entry("Row", r, commands, inputs, cols: cols, varying: varying)
        end
        Array(bp["summary"]).each { |s| out << entry("Summary", s, commands, inputs) }
      when "grid"
        Array(bp["columns"]).each { |c| out << entry("Column", c, commands, inputs, per_security: true) }
        Array(bp["stats"] || %w[median mean]).each { |st| out << { "where" => "Summary row", "label" => st.capitalize, "kind" => "formula", "example" => "=#{st == 'median' ? 'MEDIAN' : 'AVERAGE'}(column)", "meaning" => "The #{st} of each column across the securities" } }
      when "sensitivity"
        out << { "where" => "Grid", "label" => "#{bp.dig('row_param', 'label')} × #{bp.dig('col_param', 'label')}", "kind" => "formula",
                 "example" => bp["formula"], "meaning" => "Recomputes the result for each pair of #{bp.dig('row_param', 'label')} (rows) and #{bp.dig('col_param', 'label')} (columns), reading #{bp['source']}" }
      when "chart"
        out << { "where" => "Chart", "label" => bp["title"].to_s, "kind" => "chart", "example" => "#{bp['chart'] || 'Line'} chart of #{Array(bp['series']).join(', ')}",
                 "meaning" => "Plots #{Array(bp['series']).map(&:humanize).join(', ')} from #{bp['source']}" }
      end
      out
    end

    def entry(where, r, commands, inputs, cols: [], varying: [], per_security: false)
      if r["command"]
        c = commands[r["command"]]
        params = r["params"].to_h
        vary = varying.select { |v| cols.any? { |col| col["params"].to_h.key?(v) } }
        vary_text = vary.map { |v| vals = cols.map { |col| col.dig("params", v) }.compact; "#{v}: #{vals.first}…#{vals.last}" }.join(", ")
        example = c ? example_formula(c, params.merge(cols.first&.dig("params").to_h), inputs, per_security) : nil
        { "where" => where, "label" => r["label"].to_s, "kind" => "command", "key" => r["command"], "status" => c&.dig(:status) || c&.dig("status") || "missing",
          "syntax" => c&.dig(:syntax) || c&.dig("syntax"), "example" => example, "varies" => vary_text.presence,
          "meaning" => [c&.dig(:description) || c&.dig("description"), (per_security ? "for each security in the list" : nil)].compact.join(" ").presence || r["label"].to_s }
      else
        { "where" => where, "label" => r["label"].to_s, "kind" => "formula", "example" => r["formula"].to_s,
          "meaning" => describe_formula(r["formula"].to_s, inputs) }
      end
    end

    def example_formula(c, params, inputs, per_security)
      syntax = c[:syntax] || c["syntax"]
      defaults = (c[:defaults] || c["defaults"]).to_h
      syntax.gsub(/\{([a-z_]+)\}/) do
        k = Regexp.last_match(1)
        if k == "security" then per_security ? "A{row}" : "#{inputs['security'] || 'Security'} cell"
        elsif inputs.key?(k) then "#{inputs[k]} cell"
        else (params[k] || defaults[k]).to_s.presence || "{#{k}}"
        end
      end
    end

    def describe_formula(f, inputs)
      f.gsub(/\{row:([a-z0-9_]+)\}/) { Regexp.last_match(1).humanize.downcase }
       .gsub(/\{row_sum:([a-z0-9_]+)\}/) { "the sum of #{Regexp.last_match(1).humanize.downcase}" }
       .gsub(/\{row_last:([a-z0-9_]+)\}/) { "the last #{Regexp.last_match(1).humanize.downcase}" }
       .gsub(/\{(?:src_row|src_prev|src_cell|src_row_range|src_row_last):([a-z0-9_]+)\}/) { "#{Regexp.last_match(1).humanize.downcase} (source sheet)" }
       .gsub(/\{cell:([a-z0-9_]+)\}/) { Regexp.last_match(1).humanize.downcase }
       .gsub(/\{input:([a-z0-9_]+)\}/) { (inputs[Regexp.last_match(1)] || Regexp.last_match(1).humanize).downcase }
       .gsub(/\{col:([a-z0-9_]+)\}/) { "the column's #{Regexp.last_match(1)}" }
       .delete_prefix("=").then { |t| "Computed: #{t}" }
    end

    def formulas_md(bp, commands, provider:, title:, new_commands: [])
      inv = inventory(bp, commands)
      lines = ["# Formulas: #{title}", "", "#{provider_name(provider)} · #{inv.size} formula pattern#{inv.size == 1 ? '' : 's'}", "",
               "| Where | Label | Source | Example | Varies | Meaning |", "|---|---|---|---|---|---|"]
      inv.each do |e|
        src = case e["kind"]
              when "command" then "`#{e['key']}` (#{e['status']})"
              when "chart" then "chart"
              else "computed"
              end
        lines << "| #{e['where']} | #{md(e['label'])} | #{src} | `#{md(e['example'])}` | #{md(e['varies'])} | #{md(e['meaning'])} |"
      end
      if new_commands.any?
        lines += ["", "## New commands (unverified)", "", "Not in the #{provider_name(provider)} library yet; added unverified for someone with access to check.", "",
                  "| Key | Name | Category | Syntax |", "|---|---|---|---|"]
        new_commands.each { |c| lines << "| `#{c['key']}` | #{md(c['name'])} | #{md(c['category'])} | `#{md(c['syntax'])}` |" }
      end
      lines.join("\n")
    end

    def structure_md(bp, title:, purpose:, provider:, dependencies: [], risks: [], observed: nil)
      bp = bp.to_h
      inputs = Array(bp["inputs"])
      lines = ["# Structure: #{title}", "", purpose.to_s, "",
               "- Provider: #{provider_name(provider)}", "- Shape: #{bp['kind'] || 'table'}#{bp['sheet'] ? " on sheet “#{bp['sheet']}”" : ''}"]
      lines << "- Observed: #{observed}" if observed
      lines += ["", "## Layout", ""] + Worksheets.outline(bp).map { |l| "- #{l}" }
      if inputs.any?
        lines += ["", "## Inputs", "", "| Key | Label | Type | Default |", "|---|---|---|---|"]
        inputs.each { |i| lines << "| `#{i['key']}` | #{md(i['label'])} | #{i['type'] || 'value'} | #{md(i['default'].to_s.lines.first.to_s.strip)} |" }
      end
      if Array(bp["columns"]).any? && (bp["kind"] || "table") == "table"
        lines += ["", "## Columns", "", Array(bp["columns"]).map { |c| "#{c['label']}#{c['params'].present? ? " (#{c['params'].map { |k, v| "#{k}=#{v}" }.join(', ')})" : ''}" }.join(" · ")]
      end
      lines += ["", "## Depends on", ""] + dependencies.map { |d| "- #{d}" } if dependencies.any?
      lines += ["", "## Assumptions and risks", ""] + risks.map { |r| "- #{r}" } if risks.any?
      lines.join("\n")
    end

    # Agent directions for a worksheet skill's road: what the sheet attempts and every formula on it.
    def road_directions(skill_title:, description:, bp:, commands:, provider:, guide_path: nil)
      inv = inventory(bp, commands)
      verified = inv.count { |e| e["kind"] == "command" && e["status"] == "verified" }
      cmds = inv.count { |e| e["kind"] == "command" }
      lines = ["# Road: #{skill_title}", "", "## What this sheet is attempting", "", description.to_s, "",
               "## How it's laid out", ""] + Worksheets.outline(bp).map { |l| "- #{l}" }
      lines += ["", "## Every formula", "", "| Where | Label | Source | Example | Varies | Meaning |", "|---|---|---|---|---|---|"]
      inv.each do |e|
        src = e["kind"] == "command" ? "`#{e['key']}` (#{e['status']})" : e["kind"]
        lines << "| #{e['where']} | #{md(e['label'])} | #{src} | `#{md(e['example'])}` | #{md(e['varies'])} | #{md(e['meaning'])} |"
      end
      lines += ["", "## Checking it", "",
                "- #{verified} of #{cmds} #{provider_name(provider)} commands are verified; treat results from the others as unconfirmed.",
                "- Confirm units (usually millions), currency and fiscal periods match the column headers."]
      lines << "- This sheet reads “#{bp['source']}”: build that one first, with the same inputs." if bp.to_h["source"]
      lines += ["", "## Capturing or changing it", "",
                "Follow Observe → Interpret → Document (pieces and structures) → Write" + (guide_path ? " in the #{provider_name(provider)} agent guide (`#{guide_path}`)." : ".")]
      lines.join("\n")
    end

    def md(s) = s.to_s.gsub("|", "\\|").gsub("\n", " ")
  end
end
