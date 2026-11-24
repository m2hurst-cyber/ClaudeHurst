module Capture
  # Worksheet blueprints carried by skills (source["worksheet"]): what the Office add-in builds.
  # See app/javascript/addin/worksheet_builder.js for the layout and template rules.
  module Worksheets
    KINDS = %w[table grid sensitivity chart].freeze
    TOKEN = /\{([a-z_]+)(?::([A-Za-z0-9_\-]+))?\}/

    module_function

    def command_keys(bp)
      return [] unless bp.is_a?(Hash)
      (Array(bp["rows"]) + Array(bp["summary"]) + Array(bp["columns"])).filter_map { |r| r["command"] }.uniq
    end

    # Skill names this blueprint reads from (a chart's or sensitivity grid's source), recursively.
    def source_chain(bp, lookup)
      out = []
      name = bp.is_a?(Hash) ? bp["source"] : nil
      while name && !out.include?(name)
        out << name
        name = lookup.call(name)&.dig("source")
      end
      out
    end

    # Problems with a blueprint: unknown kind, unknown commands or sources, references to rows that don't exist.
    def problems(bp, commands:, skills:)
      out = []
      return ["worksheet must be a mapping"] unless bp.is_a?(Hash)
      kind = bp["kind"] || "table"
      out << "unknown worksheet kind #{kind}" unless KINDS.include?(kind)
      out << "a #{kind} needs a sheet name" if kind != "chart" && bp["sheet"].blank?
      command_keys(bp).each { |k| out << "unknown command #{k}" unless commands.include?(k) }
      if bp["source"]
        src = skills[bp["source"]]
        out << "unknown source #{bp['source']}" unless src
        if src && %w[chart].include?(kind)
          keys = (src["kind"] || "table") == "grid" ? Array(src["columns"]).map { |c| c["key"] } : Array(src["rows"]).map { |r| r["key"] }
          Array(bp["series"]).each { |k| out << "chart series #{k} isn't in #{bp['source']}" unless keys.include?(k) }
        end
      end
      row_keys = Array(bp["rows"]).map { |r| r["key"] }
      summary_keys = Array(bp["summary"]).map { |r| r["key"] }
      input_keys = Array(bp["inputs"]).map { |r| r["key"] }
      src = bp["source"] && skills[bp["source"]]
      src_rows = src ? Array(src["rows"]).map { |r| r["key"] } : []
      src_cells = src ? Array(src["summary"]).map { |r| r["key"] } : []
      (Array(bp["rows"]) + Array(bp["summary"]) + [bp]).each do |r|
        r["formula"].to_s.scan(TOKEN).each do |type, key|
          next if key.nil? # {row} and {col} in a sensitivity grid
          ok = case type
               when "row", "row_range", "row_sum", "row_last" then row_keys.include?(key)
               when "cell" then summary_keys.include?(key)
               when "input" then input_keys.include?(key)
               when "src_row", "src_prev", "src_row_range", "src_row_last" then src_rows.include?(key)
               when "src_cell" then src_cells.include?(key)
               else true
               end
          out << "#{r['key'] || 'formula'}: unknown {#{type}:#{key}}" unless ok
        end
      end
      out
    end

    # Plain-language outline used to generate a skill's instructions and shown on its card.
    def outline(bp)
      case bp["kind"] || "table"
      when "table"
        cols = Array(bp["columns"]).map { |c| c["label"] }
        ["Sheet “#{bp['sheet']}”: #{Array(bp['rows']).map { |r| r['label'] }.join(', ')}#{cols.any? ? " for #{cols.first}–#{cols.last}" : ''}",
         (Array(bp["summary"]).any? ? "Summary: #{Array(bp['summary']).map { |r| r['label'] }.join(', ')}" : nil)].compact
      when "grid"
        ["Sheet “#{bp['sheet']}”: one row per #{Array(bp['inputs']).find { |i| i['type'] == 'list' }&.dig('label')&.downcase || 'security'}; columns #{Array(bp['columns']).map { |c| c['label'] }.join(', ')}",
         (Array(bp["stats"] || %w[median mean]).any? ? "Median and mean rows" : nil)].compact
      when "sensitivity"
        ["Sheet “#{bp['sheet']}”: #{bp.dig('row_param', 'label')} (#{Array(bp.dig('row_param', 'values')).first}–#{Array(bp.dig('row_param', 'values')).last}) by #{bp.dig('col_param', 'label')} (#{Array(bp.dig('col_param', 'values')).first}–#{Array(bp.dig('col_param', 'values')).last})"]
      when "chart"
        ["#{bp['chart'] || 'Line'} chart of #{Array(bp['series']).map(&:humanize).join(', ')} on the source sheet"]
      end
    end
  end
end
