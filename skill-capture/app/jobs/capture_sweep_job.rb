# Hourly: purge expired events, detect repeated workflows, draft the new ones.
class CaptureSweepJob < ApplicationJob
  queue_as :default

  def perform
    return unless Capture::Config.enabled?
    UsageEvent.expired.in_batches.delete_all
    result = Capture::WorkflowDetector.call
    result.created.each { |c| SkillDraftJob.perform_later(c.id) }
    Capture::ChainDetector.call
    Capture::Bounties.sweep(Capture::Congestion.call)
    # Classify anything published without a classification yet (e.g. after taxonomy changes).
    classified = SkillClassification.pluck(:skill_name)
    Skill.published.where.not(name: classified).find_each { |s| ClassifySkillJob.perform_later(s.name) }
    Rails.logger.info("Capture sweep: #{result.patterns.size} patterns, #{result.created.size} new, #{result.updated.size} updated")
  end
end
