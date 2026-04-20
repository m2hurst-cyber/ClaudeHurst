module ApplicationHelper
  include Pagy::Frontend

  def status_badge(status)
    color = case status.to_s
            when "draft", "planned", "lead", "prospect" then "bg-slate-200 text-slate-700"
            when "sent", "released", "qualified", "proposal", "signed", "partial", "in_progress" then "bg-sky-100 text-sky-800"
            when "accepted", "paid", "completed", "closed", "closed_won", "active" then "bg-emerald-100 text-emerald-800"
            when "rejected", "void", "cancelled", "closed_lost", "churned", "expired", "terminated" then "bg-red-100 text-red-800"
            when "overdue" then "bg-orange-100 text-orange-800"
            when "negotiation" then "bg-purple-100 text-purple-800"
            else "bg-slate-100 text-slate-700"
            end
    content_tag :span, status.to_s.humanize, class: "inline-block text-xs font-medium px-2 py-0.5 rounded #{color}"
  end

  def mobile_nav_link(label, path, icon)
    active = current_page?(path)
    classes = [
      "flex min-h-14 flex-col items-center justify-center gap-1 rounded-xl px-2 transition active:scale-95",
      active ? "bg-white text-slate-950 shadow-sm" : "text-slate-500 hover:bg-white hover:text-slate-950 hover:shadow-sm"
    ].join(" ")

    link_to path, class: classes, aria: { label: label } do
      safe_join([
        content_tag(:span, icon, class: "grid h-6 w-6 place-items-center rounded-lg bg-white text-sm shadow-sm", aria: { hidden: true }),
        content_tag(:span, label)
      ])
    end
  end

  def money(cents, currency = "USD")
    Money.new(cents.to_i, currency).format
  end

  def nice_datetime(t)
    return "-" unless t
    t.in_time_zone.strftime("%Y-%m-%d %H:%M")
  end

  def nice_date(d)
    return "-" unless d
    d.strftime("%Y-%m-%d")
  end
end
