module PricingHelper
  # Traffic tiers wear the fixed status palette (never a series color), always with an icon and a label.
  STATUS = [
    { color: "#0ca30c", icon: "●" }, # good
    { color: "#fab219", icon: "▲" }, # warning
    { color: "#ec835a", icon: "▲" }, # serious
    { color: "#d03b3b", icon: "■" }  # critical
  ].freeze

  def schedule = @schedule ||= PricingSchedule.current

  def tier_status(tier_key)
    rank = schedule.rank(tier_key)
    return nil unless rank
    n = schedule.tiers.size
    idx = n <= 1 ? 0 : (rank * (STATUS.size - 1).to_f / (n - 1)).round
    STATUS[idx].merge(label: schedule.tier(tier_key)["label"], rank: rank)
  end

  def tier_badge(tier_key)
    s = tier_status(tier_key)
    return tag.span("Not enough traffic yet", class: "text-xs text-slate-500") unless s
    tag.span(class: "inline-flex items-center gap-1 text-xs font-medium text-slate-900") do
      safe_join([tag.span(s[:icon], style: "color: #{s[:color]}", "aria-hidden": true), s[:label]])
    end
  end

  def credits(amount)
    "#{number_with_delimiter(amount.to_d.round(2).to_s('F').sub(/\.0\z/, ''))} #{schedule.currency}"
  end

  def minutes_text(m)
    return "—" if m.nil?
    return "#{m.round} min" if m < 90
    return "#{(m / 60.0).round(1)} h" if m < 60 * 36
    "#{(m / 1440.0).round(1)} days"
  end
end
