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
    name.length <= 3 ? name.upcase : name.tr("-_", "  ").titleize
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
end
