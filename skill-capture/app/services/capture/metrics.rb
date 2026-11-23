module Capture
  module Metrics
    module_function

    def summary
      counts = SkillCandidate.group(:status).count
      decided = counts.values_at("approved", "rejected", "dismissed").compact.sum
      approved = counts["approved"].to_i
      lead = SkillCandidate.where(status: "approved").where.not(reviewed_at: nil)
                           .pluck(:created_at, :reviewed_at).map { |a, b| b - a }.sort
      {
        detected: counts.values.sum,
        open: counts.values_at("detected", "drafted").compact.sum,
        approved: approved,
        approval_rate: decided.zero? ? nil : (approved.to_f / decided).round(2),
        median_hours_to_approval: lead.empty? ? nil : (lead[lead.size / 2] / 3600.0).round(1),
        published_skills: Skill.published.count,
        events_last_7_days: UsageEvent.where("occurred_at > ?", 7.days.ago).count,
        active_sources: Source.active.count
      }
    end
  end
end
