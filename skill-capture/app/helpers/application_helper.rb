module ApplicationHelper
  include Pagy::Frontend

  BADGE = {
    "detected" => "bg-slate-200 text-slate-800", "drafted" => "bg-sky-100 text-sky-800",
    "approved" => "bg-emerald-100 text-emerald-800", "published" => "bg-emerald-100 text-emerald-800",
    "rejected" => "bg-red-100 text-red-800", "dismissed" => "bg-slate-100 text-slate-600",
    "superseded" => "bg-amber-100 text-amber-900", "deprecated" => "bg-red-100 text-red-800"
  }.freeze

  def status_badge(status)
    tag.span(status.to_s.humanize, class: "inline-block text-xs font-medium px-2 py-0.5 rounded #{BADGE.fetch(status.to_s, 'bg-slate-100 text-slate-700')}")
  end

  # "finance" → "Finance", "hr" → "HR", "sales-ops" → "Sales Ops"
  def area_name(name)
    return "No area" if name.blank? || name == Capture::SkillMap::UNASSIGNED
    return { "bql" => "BQL", "factset" => "FactSet" }[name] if %w[bql factset].include?(name)
    name.length <= 3 ? name.upcase : name.tr("-_", "  ").titleize
  end

  STAGE_STYLE = {
    "local" => ["🧪", "bg-slate-100 text-slate-800", "Local: sandbox, visible to its area and contributors"],
    "firm" => ["🏢", "bg-sky-100 text-sky-900", "Firm: available to everyone in the firm and to agents"],
    "market" => ["🌐", "bg-emerald-100 text-emerald-900", "Market: promoted beyond the firm"]
  }.freeze

  def stage_badge(stage)
    icon, cls, title = STAGE_STYLE.fetch(stage.to_s, ["", "bg-slate-100", stage.to_s])
    tag.span(class: "inline-flex items-center gap-1 text-xs font-medium px-2 py-0.5 rounded #{cls}", title: title) do
      safe_join([tag.span(icon, "aria-hidden": true), Skill::STAGE_LABELS.fetch(stage.to_s, stage.to_s.humanize)])
    end
  end

  APP_STYLE = {
    "Excel" => ["X", "#107c41"], "Word" => ["W", "#185abd"], "PowerPoint" => ["P", "#c43e1c"], "Outlook" => ["O", "#0f6cbd"],
    "Teams" => ["T", "#5b5fc7"], "Power BI" => ["BI", "#b48a00"], "SharePoint" => ["S", "#036c70"]
  }.freeze

  # An app chip: a small letter tile (product-colored) + the app's name. The name carries the meaning.
  def app_chip(app)
    letter, color = APP_STYLE.fetch(app, ["?", "#52514e"])
    tag.span(class: "inline-flex items-center gap-1 text-xs text-slate-800 border rounded px-1.5 py-0.5 bg-white") do
      safe_join([tag.span(letter, class: "inline-grid place-items-center w-4 h-4 rounded-sm text-[9px] font-bold text-white", style: "background: #{color}", "aria-hidden": true), app])
    end
  end

  FILE_STYLE = { "docx" => ["DOC", "#185abd"], "doc" => ["DOC", "#185abd"], "xlsx" => ["XLS", "#107c41"], "xls" => ["XLS", "#107c41"],
                 "csv" => ["CSV", "#107c41"], "pptx" => ["PPT", "#c43e1c"], "pdf" => ["PDF", "#b91c1c"], "link" => ["URL", "#52514e"] }.freeze

  def file_badge(resource)
    label, color = FILE_STYLE.fetch(resource.extension, [resource.extension.first(3).upcase, "#52514e"])
    tag.span(label, class: "inline-grid place-items-center w-9 h-9 shrink-0 rounded text-[10px] font-bold text-white", style: "background: #{color}", "aria-hidden": true)
  end

  def classification_source(c)
    return tag.span("Unclassified", class: "text-xs text-slate-400") unless c
    if c.confirmed
      tag.span("✓ #{c.source == 'user' ? 'Set' : 'Confirmed'} by #{c.updated_by&.name || 'a person'}", class: "text-xs text-slate-700", title: "A person set or confirmed this")
    else
      label = c.source == "ai" ? "✨ AI" : "✨ Inferred"
      tag.span("#{label}#{" · #{(c.confidence * 100).round}%" if c.confidence}", class: "text-xs text-violet-800 bg-violet-50 rounded px-1", title: c.rationale)
    end
  end

  def nice_time(t) = t ? t.in_time_zone.strftime("%Y-%m-%d %H:%M") : "—"
  def nice_date(t) = t ? t.to_date.iso8601 : "—"

  def nav_link(label, path)
    active = current_page?(path) || (path != root_path && request.path.start_with?(path))
    link_to label, path, class: "px-3 py-2 rounded text-sm #{active ? 'bg-slate-800 text-white' : 'text-slate-300 hover:text-white'}"
  end

  def btn = "inline-flex items-center px-3 py-1.5 rounded text-sm border bg-white hover:bg-slate-50"
  def btn_primary = "inline-flex items-center px-3 py-1.5 rounded text-sm bg-slate-900 text-white hover:bg-slate-700"
  def input_css = "border rounded px-2 py-1.5 w-full"

  # Minimal Markdown for skill instructions: headings, lists, quotes, bold, code. Escapes everything first.
  def skill_markdown(text)
    inline = ->(t) { ERB::Util.h(t).gsub(/\*\*(.+?)\*\*/, '<strong>\\1</strong>').gsub(/`([^`]+)`/, '<code class="text-xs bg-slate-100 px-1 rounded">\\1</code>') }
    html = []
    list = nil
    close = -> { html << "</#{list}>" if list; list = nil }
    table = nil
    code = nil
    flush = lambda do
      next unless table
      head, *body = table.reject { |r| r.all? { |c| c.match?(/\A:?-+:?\z/) } }
      html << '<div class="overflow-x-auto my-2"><table class="text-xs border-collapse min-w-full">'
      html << "<thead><tr>#{head.map { |c| %(<th class="border bg-slate-50 px-1.5 py-1 text-left font-semibold">#{inline.(c)}</th>) }.join}</tr></thead>"
      html << "<tbody>#{body.map { |r| "<tr>#{r.map { |c| %(<td class="border px-1.5 py-1 align-top">#{inline.(c)}</td>) }.join}</tr>" }.join}</tbody></table></div>"
      table = nil
    end
    text.to_s.each_line(chomp: true) do |line|
      if code
        if line.start_with?("```") then html << %(<pre class="text-xs bg-slate-50 border rounded p-2 my-2 overflow-x-auto">#{ERB::Util.h(code.join("\n"))}</pre>); code = nil
        else code << line
        end
        next
      end
      if line.match?(/\A\s*\|.*\|\s*\z/)
        close.()
        (table ||= []) << line.strip.delete_prefix("|").delete_suffix("|").split(/(?<!\\)\|/).map { |c| c.strip.gsub("\\|", "|") }
        next
      end
      flush.()
      case line
      when /\A```/
        close.()
        code = []
      when /\A(#+)\s+(.*)/
        close.()
        level = [$1.size + 1, 4].min
        html << %(<h#{level} class="font-semibold #{level == 2 ? 'text-base' : 'text-sm'} mt-3 mb-1">#{inline.($2)}</h#{level}>)
      when /\A\s*\d+\.\s+(.*)/
        (close.(); html << '<ol class="list-decimal ml-5 space-y-0.5">'; list = "ol") unless list == "ol"
        html << "<li>#{inline.($1)}</li>"
      when /\A\s*[-*]\s+(.*)/
        (close.(); html << '<ul class="list-disc ml-5 space-y-0.5">'; list = "ul") unless list == "ul"
        html << "<li>#{inline.($1)}</li>"
      when /\A>\s?(.*)/
        close.()
        html << %(<blockquote class="border-l-4 pl-2 text-slate-500 text-xs my-2">#{inline.($1)}</blockquote>)
      when /\A\s*\z/
        close.()
      else
        close.()
        html << %(<p class="my-1">#{inline.(line)}</p>)
      end
    end
    flush.()
    close.()
    html << %(<pre class="text-xs bg-slate-50 border rounded p-2 my-2">#{ERB::Util.h(code.join("\n"))}</pre>) if code
    safe_join([html.join.html_safe])
  end
end
