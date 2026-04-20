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
