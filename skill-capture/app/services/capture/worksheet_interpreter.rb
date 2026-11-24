require "anthropic"

module Capture
  # Observe → Interpret → Document → Write, for a worksheet captured from Excel.
  #
  #   Observe    the sheet's labels and formulas by cell (the add-in never sends numbers), the provider
  #              (BQL / FactSet / plain Excel), the inputs formulas point at, the blocks of cells
  #   Interpret  the shape (table, grid), the header and period columns, each row as a library command
  #              (matched against the provider's command syntax, with the parameters that vary by column)
  #              or a computed formula ({row:..}, {input:..}, {row_sum:..}), summary cells, dependencies,
  #              risks, and what the sheet is attempting
  #   Document   STRUCTURE.md, FORMULAS.md, blueprint.json (WorksheetDocs)
  #   Write      SKILL.md in the Agent Skills format, as a draft skill for the area's reviewers; formulas
  #              not in the library are added as new, unverified commands
  #
  # The deterministic rules always run and produce the blueprint; Claude (when configured) follows the
  # provider's agent guide to name and explain things: purpose, title, description, field, meanings, risks.
  class WorksheetInterpreter
    class Error < StandardError; end
    MAX_CELLS = 5000
    REF = /(?<![!A-Za-z_'])(\$?)([A-Z]{1,3})(\$?)(\d{1,6})(?![\d(A-Za-z_])/
    PROVIDER_FN = { "bql" => /\b(BQL(\.Query)?|BDP|BDH|BDS)\s*\(/i, "factset" => /\bFDS[CB]?\s*\(/i }.freeze
    FIELDS = {
      "investment-analysis/valuation/intrinsic-valuation" => /wacc|discount|terminal|dcf|present value|npv/i,
      "investment-analysis/valuation/relative-valuation" => /\bp\s*\/\s*e\b|ev\s*\/\s*ebitda|multiple|peer|comps?\b|pe_ratio|ev_ebitda/i,
      "investment-analysis/esg" => /\besg\b|environment|social|governance|sustainab/i,
      "investment-analysis/macro-analysis" => /\bgdp\b|\bcpi\b|inflation|unemploy|policy rate|treasury|\bindex\b|yield/i
    }.freeze

    def self.call(user:, payload:, client: nil) = new(user, payload, client).call

    def initialize(user, payload, client)
      @user, @payload, @client = user, payload, client
      @risks = []
      @new_commands = []
    end

    def call
      observe!
      interpret!
      enrich_with_ai!
      capture = document!
      write!(capture)
      capture
    end

    # ---------- Observe ----------
    def observe!
      @sheet = @payload["sheet"].to_s.strip.first(31).presence || raise(Error, "No sheet name")
      @cells = {}
      Array(@payload["cells"]).first(MAX_CELLS).each do |c|
        rc = parse(c["a"]) or next
        if c["f"].to_s.start_with?("=") then @cells[rc] = { f: c["f"].to_s.first(1000) }
        elsif c["t"].to_s.strip.present? then @cells[rc] = { t: c["t"].to_s.strip.first(120) }
        elsif c["n"] then @cells[rc] = { n: true }
        end
      end
      raise Error, "The sheet is empty" if @cells.empty?
      formulas = @cells.values.filter_map { |v| v[:f] }
      raise Error, "No formulas on this sheet to document" if formulas.empty?
      counts = PROVIDER_FN.transform_values { |re| formulas.count { |f| f.match?(re) } }
      @provider = counts.max_by { |_, n| n }.then { |k, n| n.positive? ? k : "excel" }
      @commands = FormulaCommand.live.where(provider: @provider).to_a
      @matchers = @commands.map { |c| [c, matcher(c.syntax)] }
      @inputs = {} # [r,c] => {key, label, param}
      formulas.each { |f| f.scan(REF) { |d1, col, d2, row| rc = [row.to_i, col_num(col)]; (@inputs[rc] ||= {}) if d1 == "$" && d2 == "$" && !@cells.dig(rc, :f) } }
      @inputs.each_key do |rc|
        label = text_at(rc[0], rc[1] - 1) || text_at(rc[0] - 1, rc[1]) || "Input #{addr(rc)}"
        @inputs[rc] = { "label" => label.sub(/:\z/, ""), "key" => slug(label), "cell" => addr(rc), "default" => text_at(*rc) || "" }
      end
      @observed_summary = "#{@cells.size} filled cells, #{formulas.size} formulas, #{@inputs.size} input#{@inputs.size == 1 ? '' : 's'}, provider #{WorksheetDocs.provider_name(@provider)}"
    end

    # ---------- Interpret ----------
    def interpret!
      @title = text_at(1, 0) || @sheet
      header_row = find_header
      @blueprint = if header_row && grid?(header_row) then interpret_grid(header_row)
                   elsif header_row then interpret_table(header_row)
                   end
      @risks << "Couldn't find a header row with period or field columns; documented the formulas only, without a buildable blueprint." unless @blueprint
      @risks << "Numbers on the sheet aren't captured: input defaults (rates, dates) need filling in." if @inputs.values.any? { |i| i["default"].blank? }
      literals = @cells.values.filter_map { |v| v[:f] }.flat_map { |f| f.scan(/"([A-Z0-9.\-]+ (?:US )?(?:Equity|Index|Comdty|Curncy|Govt|Corp))"|"([A-Z0-9.]+-[A-Z]{2})"/i).flatten.compact }.uniq
      @risks << "Hard-coded securities inside formulas (#{literals.first(4).join(', ')}): make them inputs so the skill works for any security." if literals.any?
      @dependencies = @cells.values.filter_map { |v| v[:f] }.flat_map { |f| f.scan(/'?([A-Za-z0-9 _\-]+)'?!/).flatten }.uniq.reject { |s| s == @sheet }
      @dependencies.each { |d| @risks << "Reads the “#{d}” sheet: build that one first." }
      @risks << "#{@new_commands.size} formula#{@new_commands.size == 1 ? '' : 's'} not in the #{WorksheetDocs.provider_name(@provider)} library: added as new, unverified commands." if @new_commands.any?
      text = ([@title, @sheet] + @cells.values.filter_map { |v| v[:t] } + Worksheets.command_keys(@blueprint.to_h)).join(" ")
      @field = FIELDS.find { |_, re| text.match?(re) }&.first || "investment-analysis/financial-analysis"
      kind = @blueprint&.dig("kind") || "worksheet"
      rows = Array(@blueprint&.dig("rows") || @blueprint&.dig("columns")).map { |r| r["label"] }.first(5)
      @purpose = "Builds a #{kind} of #{rows.join(', ').downcase.presence || 'formulas'}#{@blueprint && (cols = Array(@blueprint['columns'])).any? && kind == 'table' ? " for #{cols.first['label']}–#{cols.last['label']}" : ''} from #{WorksheetDocs.provider_name(@provider)} data."
      @description = "#{@purpose} Use when you need the “#{@title}” worksheet for a new #{kind == 'grid' ? 'set of securities' : 'security'}."
    end

    def find_header
      rows = @cells.keys.map(&:first).uniq.sort
      rows.find do |r|
        heads = @cells.select { |(rr, c), v| rr == r && c >= 1 && v[:t] }.keys
        heads.size >= 2 && heads.any? { |(_, c)| @cells.dig([r + 1, c], :f) }
      end
    end

    def header_cols(h) = @cells.select { |(r, c), v| r == h && c >= 1 && v[:t] }.keys.map(&:last).sort

    def data_rows(h)
      cols = header_cols(h)
      out = []
      r = h + 1
      while cols.any? { |c| @cells.dig([r, c], :f) }
        out << r
        r += 1
      end
      out
    end

    def grid?(h)
      rows = data_rows(h)
      rows.size >= 2 && rows.all? { |r| text_at(r, 0) && header_cols(h).any? { |c| @cells.dig([r, c], :f).to_s.match?(/\$?A\$?#{r}(?!\d)/) } }
    end

    def interpret_table(h)
      cols = header_cols(h)
      rows = data_rows(h)
      @row_keys = {}
      rows.each { |r| @row_keys[r] = unique(slug(text_at(r, 0) || "row #{r}"), @row_keys.values) }
      col_params = cols.map { {} }
      bp_rows = rows.map { |r| interpret_row(r, cols, col_params) }
      summary = interpret_summary(rows.last.to_i + 1, cols)
      inputs = @inputs.values.map { |i| { "key" => i["key"], "label" => i["label"], "default" => i["default"] } }
      { "kind" => "table", "sheet" => @sheet, "title" => @title, "row_header" => text_at(h, 0).to_s,
        "inputs" => inputs, "columns" => cols.each_with_index.map { |c, i| { "label" => text_at(h, c), "params" => col_params[i] }.reject { |_, v| v.blank? } },
        "rows" => bp_rows, "summary" => summary }.reject { |k, v| v.blank? && !%w[rows].include?(k) }
    end

    def interpret_row(r, cols, col_params)
      label = text_at(r, 0) || "Row #{r}"
      key = @row_keys[r]
      fs = cols.map { |c| @cells.dig([r, c], :f) }
      if fs.compact.all? { |f| provider_formula?(f) }
        m = fs.map { |f| f && match_command(f) }
        if m.compact.size == fs.compact.size && m.compact.map { |x| x[0].key }.uniq.size == 1
          cmd = m.compact.first[0]
          params = varying_params(m.map { |x| x && x[1] }, col_params, cols, cmd)
          return { "key" => key, "label" => label, "command" => cmd.key, "params" => params }.reject { |_, v| v.blank? }
        end
        nc = propose_command(label, fs.compact, col_params, cols)
        return { "key" => key, "label" => label, "command" => nc["key"] }
      end
      { "key" => key, "label" => label, "formula" => template(fs.compact.first.to_s, r, cols, cols[fs.index(fs.compact.first)], col_params) }
    end

    def interpret_summary(start, cols)
      @summary_keys = {}
      rows = @cells.keys.select { |(r, c)| r >= start && c == cols.first && @cells.dig([r, c], :f) }.map(&:first).sort
      rows.each { |r| @summary_keys[r] = unique(slug(text_at(r, 0) || "cell #{r}"), @row_keys.values + @summary_keys.values) }
      rows.map do |r|
        f = @cells.dig([r, cols.first], :f)
        label = text_at(r, 0) || "Cell #{r}"
        if provider_formula?(f) && (m = match_command(f))
          { "key" => @summary_keys[r], "label" => label, "command" => m[0].key, "params" => fixed_params(m[1], m[0]) }.reject { |_, v| v.blank? }
        elsif provider_formula?(f)
          nc = propose_command(label, [f], [{}], [cols.first])
          { "key" => @summary_keys[r], "label" => label, "command" => nc["key"] }
        else
          { "key" => @summary_keys[r], "label" => label, "formula" => template(f, r, cols, nil, nil) }
        end
      end
    end

    def interpret_grid(h)
      cols = header_cols(h)
      rows = data_rows(h)
      securities = rows.map { |r| text_at(r, 0) }.compact
      list_label = text_at(h, 0) || "Security"
      columns = cols.map do |c|
        label = text_at(h, c)
        f = @cells.dig([rows.first, c], :f).to_s
        key = unique(slug(label), [])
        sec_f = f.gsub(/\$?A\$?#{rows.first}(?!\d)/, "$B$999") # stand-in so matching binds {security}
        if (m = match_command(sec_f, security_ref: "$B$999"))
          { "key" => key, "label" => label, "command" => m[0].key, "params" => fixed_params(m[1].except("security"), m[0]) }.reject { |_, v| v.blank? }
        else
          nc = propose_command(label, [f.gsub(/\$?A\$?#{rows.first}(?!\d)/, "{security}")], [{}], [c], preset_security: true)
          { "key" => key, "label" => label, "command" => nc["key"] }
        end
      end
      stats = @cells.select { |(r, c), v| r > rows.last && c.zero? && v[:t].to_s.match?(/\A(median|mean|average)\z/i) }.values.map { |v| v[:t].downcase.sub("average", "mean") }
      inputs = [{ "key" => slug(list_label), "label" => list_label, "type" => "list", "default" => securities.join("\n") }] +
               @inputs.values.map { |i| { "key" => i["key"], "label" => i["label"], "default" => i["default"] } }
      { "kind" => "grid", "sheet" => @sheet, "title" => @title, "inputs" => inputs, "columns" => columns, "stats" => stats }
    end

    # ---------- formula matching ----------
    def provider_formula?(f) = @provider != "excel" && f.to_s.match?(PROVIDER_FN[@provider])

    def matcher(syntax)
      names = []
      src = Regexp.escape(syntax).gsub(/\\\{([a-z_]+)\\\}/) do
        n = Regexp.last_match(1)
        if names.include?(n) then "\\k<#{n}>" else names << n; n == "security" ? "(?<#{n}>[^,]+?)" : "(?<#{n}>[^,\"()]+?)" end
      end
      Regexp.new("\\A#{src.gsub('\\ ', '\\s*')}\\z", Regexp::IGNORECASE)
    end

    def match_command(f, security_ref: nil)
      norm = f.gsub(/\s+/, " ")
      @matchers.each do |c, re|
        m = re.match(norm) or next
        params = m.names.to_h { |n| [n, m[n]] }
        return [c, params]
      end
      nil
    end

    def input_for(ref)
      return nil unless ref.to_s.match?(/\A\$[A-Z]+\$\d+\z/)
      rc = parse(ref)
      @inputs[rc]
    end

    # Parameters: bound to inputs (renaming the input's key to the parameter), constant (row params) or varying (column params).
    def varying_params(per_col, col_params, cols, cmd)
      row = {}
      (per_col.compact.first || {}).each_key do |name|
        vals = per_col.map { |p| p && p[name] }
        if (inp = input_for(vals.compact.first))
          inp["key"] = name
          next
        end
        if vals.compact.uniq.size > 1
          vals.each_with_index { |v, i| col_params[i][name] = typed(v) unless v.nil? }
        elsif cmd.defaults[name].to_s != vals.compact.first.to_s
          row[name] = typed(vals.compact.first)
        end
      end
      row
    end

    def fixed_params(params, cmd)
      params.each_with_object({}) do |(name, v), h|
        if (inp = input_for(v)) then inp["key"] = name
        elsif name != "security" && cmd.defaults[name].to_s != v.to_s then h[name] = typed(v)
        end
      end
    end

    def typed(v) = v.to_s.match?(/\A-?\d+\z/) ? v.to_i : (v.to_s.match?(/\A-?\d+\.\d+\z/) ? v.to_f : v.to_s)

    # A formula the library doesn't have: generalize it (inputs → placeholders, numbers that vary by
    # column → {fpo}/{p2}…) and add it as a new, unverified command.
    def propose_command(label, formulas, col_params, cols, preset_security: false)
      key = unique(slug(label), @commands.map(&:key) + @new_commands.map { |c| c["key"] })
      generalized = formulas.map do |f|
        f.gsub(/\$[A-Z]+\$\d+/) do |ref|
          inp = input_for(ref)
          next ref unless inp
          name = inp["key"] == "security" || preset_security || ref == formulas.first[/\$[A-Z]+\$\d+/] ? "security" : inp["key"]
          inp["key"] = name
          "{#{name}}"
        end
      end
      skeletons = generalized.map { |g| g.split(/(-?\d+(?:\.\d+)?)/) }
      syntax = generalized.first.dup
      if skeletons.size > 1 && skeletons.map(&:size).uniq.size == 1
        varying = (0...skeletons.first.size).select { |i| i.odd? && skeletons.map { |s| s[i] }.uniq.size > 1 }
        names = varying.each_with_index.to_h { |pos, n| [pos, n.zero? ? "fpo" : "p#{n + 1}"] }
        parts = skeletons.first.each_with_index.map { |s, i| names[i] ? "{#{names[i]}}" : s }
        syntax = parts.join
        varying.each { |pos| skeletons.each_with_index { |s, ci| col_params[ci][names[pos]] = typed(s[pos]) } }
      end
      existing = @new_commands.find { |c| c["syntax"] == syntax }
      return existing if existing
      cmd = { "key" => key, "name" => label, "category" => "Captured", "syntax" => syntax, "example" => formulas.first }
      @new_commands << cmd
      cmd
    end

    # A computed formula as a template: references to rows of the table (same column) → {row:key},
    # sums over a row → {row_sum:key}, the last column of a row → {row_last:key}, summary cells → {cell:key},
    # inputs → {input:key}, numbers that vary by column → {col:n}.
    def template(f, r, cols, col, col_params)
      t = f.gsub(/SUM\(\$?([A-Z]+)\$?(\d+):\$?([A-Z]+)\$?(\d+)\)/i) do
        a, ra, b, rb = Regexp.last_match.captures
        key = @row_keys[ra.to_i]
        key && ra == rb && col_num(a) == cols.first && col_num(b) == cols.last ? "{row_sum:#{key}}" : Regexp.last_match(0)
      end
      t.gsub(REF) do |m|
        d1, c, d2, rr = Regexp.last_match.captures
        rc = [rr.to_i, col_num(c)]
        if d1 == "$" && d2 == "$" && (inp = @inputs[rc]) then "{input:#{inp['key']}}"
        elsif @summary_keys&.key?(rc[0]) && rc[1] == cols.first then "{cell:#{@summary_keys[rc[0]]}}"
        elsif (k = @row_keys[rc[0]]) && col && rc[1] == col then "{row:#{k}}"
        elsif (k = @row_keys[rc[0]]) && rc[1] == cols.last then "{row_last:#{k}}"
        else
          @risks << "“#{text_at(r, 0) || "Row #{r}"}” refers to #{m}, outside the table: check it after building." unless @risks.any? { |x| x.include?(m) }
          m
        end
      end.then do |tpl|
        next tpl unless col_params && col
        others = cols.filter_map { |c| (x = @cells.dig([r, c], :f)) && [c, x] }
        nums = others.map { |_, x| x.scan(/\^(\d+)/).flatten }
        if nums.map(&:size).uniq == [1] && nums.flatten.uniq.size > 1
          others.each_with_index { |(c, _), i| col_params[cols.index(c)]["n"] = nums[i].first.to_i }
          tpl.sub(/\^\d+/, "^{col:n}")
        else tpl
        end
      end
    end

    # ---------- AI pass ----------
    SCHEMA = {
      type: "object", additionalProperties: false,
      required: %w[title purpose description field_path risks meanings command_names],
      properties: {
        title: { type: "string" }, purpose: { type: "string" }, description: { type: "string" },
        field_path: { type: "string" }, risks: { type: "array", items: { type: "string" } },
        meanings: { type: "array", items: { type: "object", additionalProperties: false, required: %w[index meaning], properties: { index: { type: "integer" }, meaning: { type: "string" } } } },
        command_names: { type: "array", items: { type: "object", additionalProperties: false, required: %w[key name category], properties: { key: { type: "string" }, name: { type: "string" }, category: { type: "string" } } } }
      }
    }.freeze

    def enrich_with_ai!
      @by = "rules"
      return unless @client || Config.llm_enabled?
      guide = Playbook.all.find { |pb| pb.pack? && pb.provider == @provider }&.guide
      listing = @cells.sort.map { |rc, v| "#{addr(rc)}: #{v[:f] || (v[:t] ? %("#{v[:t]}") : '(number)')}" }.first(800).join("\n")
      inv = WorksheetDocs.inventory(@blueprint.to_h, command_map)
      fields = Field.where("path LIKE 'investment-analysis%'").pluck(:path)
      msg = (@client || Anthropic::Client.new).beta.messages.create(
        model: Config.llm_model, max_tokens: 8_000,
        system_: "#{guide || 'Follow Observe → Interpret → Document → Write.'}\n\nYou are on the Interpret pass. The rules have already observed the sheet and drafted a blueprint and a formula inventory. Explain what the sheet is attempting, write the skill's title and Agent Skills description, choose the field (one of: #{fields.join(', ')}), add risks, give a plain meaning for each inventory entry by its index, and name each new command. Never invent provider fields or codes.",
        output_config: { effort: :medium, format: { type: :json_schema, schema: SCHEMA } },
        fallbacks: :default, betas: ["server-side-fallback-2026-07-01"],
        messages: [{ role: "user", content: { sheet: @sheet, provider: @provider, observed: listing, blueprint: @blueprint, inventory: inv.each_with_index.map { |e, i| e.merge("index" => i) }, new_commands: @new_commands, risks: @risks }.to_json }]
      )
      raise ClaudeDrafter::DraftError, "declined" if msg.stop_reason.to_s == "refusal"
      d = JSON.parse(msg.content.select { |b| b.type.to_s == "text" }.map(&:text).join)
      @title = d["title"].to_s.squish.first(120).presence || @title
      @purpose = d["purpose"].to_s.squish.presence || @purpose
      @description = d["description"].to_s.squish.presence || @description
      @field = d["field_path"] if fields.include?(d["field_path"])
      @risks |= Array(d["risks"]).map { |x| x.to_s.squish }.reject(&:blank?).first(10)
      @meanings = Array(d["meanings"]).to_h { |x| [x["index"].to_i, x["meaning"].to_s.squish] }
      Array(d["command_names"]).each do |n|
        c = @new_commands.find { |x| x["key"] == n["key"] } or next
        c["name"] = n["name"].to_s.squish.presence || c["name"]
        c["category"] = n["category"].to_s.squish.presence || c["category"]
      end
      @by = "ai"
    rescue ClaudeDrafter::DraftError, Anthropic::Errors::Error, JSON::ParserError => e
      Rails.logger.warn("Worksheet capture: AI interpretation fell back to rules: #{e.class}: #{e.message}")
    end

    def command_map
      @commands.to_h { |c| [c.key, c.to_builder.stringify_keys] }
               .merge(@new_commands.to_h { |c| [c["key"], { "syntax" => c["syntax"], "status" => "unverified (new)", "name" => c["name"], "description" => "Captured from the sheet: #{c['example']}" }] })
    end

    # ---------- Document ----------
    def document!
      cmds = command_map
      inv = WorksheetDocs.inventory(@blueprint.to_h, cmds)
      inv.each_with_index { |e, i| e["meaning"] = @meanings[i] if @meanings&.dig(i).present? }
      inv = loose_inventory if inv.empty?
      WorksheetCapture.create!(
        user: @user, sheet_name: @sheet, address: @payload["address"].to_s.first(40), provider: @provider,
        observed: { "summary" => @observed_summary, "cells" => @cells.sort.map { |rc, v| { "a" => addr(rc) }.merge(v.transform_keys(&:to_s)) } },
        interpretation: { "title" => @title, "purpose" => @purpose, "description" => @description, "field" => @field,
                          "kind" => @blueprint&.dig("kind"), "dependencies" => @dependencies, "risks" => @risks },
        inventory: inv, blueprint: @blueprint || {}, interpreted_by: @by,
        structure_md: WorksheetDocs.structure_md(@blueprint || { "sheet" => @sheet }, title: @title, purpose: @purpose, provider: @provider,
                                                 dependencies: @dependencies, risks: @risks, observed: @observed_summary),
        formulas_md: formulas_md_for(inv)
      )
    end

    def formulas_md_for(inv)
      lines = ["# Formulas: #{@title}", "", "#{WorksheetDocs.provider_name(@provider)} · #{inv.size} formula pattern#{inv.size == 1 ? '' : 's'}", "",
               "| Where | Label | Source | Example | Varies | Meaning |", "|---|---|---|---|---|---|"]
      inv.each do |e|
        src = e["kind"] == "command" ? "`#{e['key']}` (#{e['status']})" : e["kind"]
        lines << "| #{e['where']} | #{WorksheetDocs.md(e['label'])} | #{src} | `#{WorksheetDocs.md(e['example'])}` | #{WorksheetDocs.md(e['varies'])} | #{WorksheetDocs.md(e['meaning'])} |"
      end
      if @new_commands.any?
        lines += ["", "## New commands (unverified)", "", "| Key | Name | Category | Syntax | Captured from |", "|---|---|---|---|---|"]
        @new_commands.each { |c| lines << "| `#{c['key']}` | #{WorksheetDocs.md(c['name'])} | #{WorksheetDocs.md(c['category'])} | `#{WorksheetDocs.md(c['syntax'])}` | `#{WorksheetDocs.md(c['example'])}` |" }
      end
      lines.join("\n")
    end

    # Without a recognisable table, document every formula pattern by where it sits.
    def loose_inventory
      @cells.select { |_, v| v[:f] }.group_by { |(r, c), v| v[:f].gsub(REF, "ref") }.map do |_, cells|
        (r, c), v = cells.first
        { "where" => cells.size > 1 ? "#{cells.size} cells from #{addr([r, c])}" : addr([r, c]), "label" => text_at(r, 0).to_s, "kind" => provider_formula?(v[:f]) ? "command" : "formula",
          "example" => v[:f], "meaning" => "Captured as written" }
      end
    end

    # ---------- Write ----------
    def write!(capture)
      if %w[bql factset].include?(@provider)
        @new_commands.each do |c|
          FormulaCommand.find_or_create_by!(provider: @provider, key: c["key"]) do |fc|
            fc.assign_attributes(name: c["name"], category: c["category"], syntax: c["syntax"], description: "Captured from #{@sheet}: #{c['example']}",
                                 origin: "capture", status: "unverified", created_by: @user)
          end
        end
      end
      bp = @blueprint
      name = unique(Naming.skill_name(@title).presence || "worksheet", Skill.distinct.pluck(:name) + SkillCandidate.open.pluck(:draft_name).compact)
      body = skill_body(capture)
      capture.update!(skill_md: "---\nname: #{name}\ndescription: #{@description.to_json}\n---\n\n#{body}")
      steps = ["Enter the inputs", "Build the #{@sheet} sheet", "Check units, periods and unverified formulas"].map { |l| ["excel.step:#{l.parameterize}", l] }
      steps.each { |k, l| ActionDefinition.find_or_create_by!(key: k) { |d| d.label = l } }
      c = SkillCandidate.create!(
        signature: "worksheet-capture:#{capture.id}", steps: steps.map(&:first), origin: "manual", proposal_kind: "save",
        domain: %w[bql factset].include?(@provider) ? @provider : @user.domains.first, requested_by: @user, status: "drafted",
        draft_name: name, draft_title: @title, draft_description: @description, draft_body: body, draft_generator: "worksheet-capture-#{@by}", drafted_at: Time.current,
        draft_tags: [@provider, @blueprint&.dig("kind")].compact, worksheet: bp.presence,
        occurrence_count: 1, distinct_actor_count: 1, contributors: [{ "key" => @user.actor_key, "name" => @user.name }],
        first_seen_at: Time.current, last_seen_at: Time.current,
        review_notes: "Captured from the “#{@sheet}” worksheet (#{@observed_summary}); interpreted by #{@by == 'ai' ? 'AI' : 'rules'}. Files: STRUCTURE.md, FORMULAS.md, blueprint.json."
      )
      capture.update!(candidate: c)
      SkillClassification.find_or_initialize_by(skill_name: name).tap do |cl|
        cl.assign_attributes(apps: ["Excel"], source: @by == "ai" ? "ai" : "rules", confirmed: false)
        cl.save!
        f = Field.find_by(path: @field)
        cl.set_fields!([f], source: cl.source) if f
      end
      c.notify_reviewers!("Worksheet captured by #{@user.name}: #{@title}")
      AuditLog.record("worksheet.captured", user: @user, subject: capture, provider: @provider, formulas: capture.inventory.size, new_commands: @new_commands.size, by: @by)
    end

    def skill_body(capture)
      bp = @blueprint.to_h
      inputs = Array(bp["inputs"]).map { |i| "- #{i['label']}#{i['default'].present? ? " (default: #{i['default'].to_s.lines.first.strip}#{i['default'].to_s.lines.size > 1 ? ', …' : ''})" : ''}" }
      inv = capture.inventory
      [
        "# #{@title}", "", "## When to use", "", @description, "",
        "## Inputs", "", (inputs.any? ? inputs.join("\n") : "- None"), "",
        "## Steps", "",
        "1. Enter the inputs#{bp['inputs'].present? ? ' (highlighted cells)' : ''}.",
        "2. Build the “#{@sheet}” sheet: Skill Capture tab › Library › this skill › Build worksheet.",
        "3. Check units, periods and any unverified formulas against #{WorksheetDocs.provider_name(@provider)}.",
        "", "## Outputs", "", *(Worksheets.outline(bp).presence || ["The “#{@sheet}” sheet"]).map { |l| "- #{l}" }, "",
        "## Formulas", "", "| Label | Source | Example |", "|---|---|---|",
        *inv.first(60).map { |e| "| #{WorksheetDocs.md(e['label'])} | #{e['kind'] == 'command' ? "`#{e['key']}`" : e['kind']} | `#{WorksheetDocs.md(e['example'])}` |" },
        "", "## Checks", "", *(@risks.presence || ["Compare a few results with the original sheet."]).map { |x| "- #{x}" }
      ].join("\n")
    end

    # ---------- helpers ----------
    def parse(a)
      m = /\A\$?([A-Z]{1,3})\$?(\d{1,6})\z/.match(a.to_s.upcase) or return nil
      [m[2].to_i, col_num(m[1])]
    end

    def col_num(letters) = letters.chars.reduce(0) { |n, ch| n * 26 + ch.ord - 64 } - 1
    def col_letters(n) = (n += 1; s = +""; (s.prepend(((n - 1) % 26 + 65).chr); n = (n - 1) / 26) while n.positive?; s)
    def addr(rc) = "#{col_letters(rc[1])}#{rc[0]}"
    def text_at(r, c) = @cells.dig([r, c], :t)
    def slug(s) = s.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "").first(40).presence || "item"

    def unique(base, taken)
      return base unless taken.include?(base)
      n = 2
      n += 1 while taken.include?("#{base}_#{n}") || taken.include?("#{base}-#{n}")
      base.include?("-") ? "#{base}-#{n}" : "#{base}_#{n}"
    end
  end
end
