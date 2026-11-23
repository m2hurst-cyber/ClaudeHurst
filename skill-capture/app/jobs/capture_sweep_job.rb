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
    # Save / extend / branch prompts for everyone who worked through the add-in recently.
    active = UsageEvent.where("occurred_at >= ?", 1.day.ago).where("actor_key LIKE 'user:%'").distinct.pluck(:actor_key)
    User.active.where(id: active.map { |k| k.delete_prefix("user:").to_i }).find_each do |u|
      PromptCheckJob.perform_now(u.id)
    rescue => e
      Rails.logger.warn("Prompts for user #{u.id} failed: #{e.class}: #{e.message}")
    end
    # Classify anything published without a classification yet (e.g. after taxonomy changes).
    classified = SkillClassification.pluck(:skill_name)
    Skill.published.where.not(name: classified).find_each { |s| ClassifySkillJob.perform_later(s.name) }
    Rails.logger.info("Capture sweep: #{result.patterns.size} patterns, #{result.created.size} new, #{result.updated.size} updated")
  end
end
