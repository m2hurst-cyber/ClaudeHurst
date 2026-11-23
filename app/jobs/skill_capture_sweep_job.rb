# Hourly: purge expired raw events, mine for repeated workflows, draft new candidates.
class SkillCaptureSweepJob < ApplicationJob
  queue_as :default

  def perform
    return unless SkillCapture::Config.enabled?

    UsageEvent.expired.in_batches.delete_all
    result = SkillCapture::WorkflowDetector.call
    result.created.each { |c| SkillDraftJob.perform_later(c.id) }
    Rails.logger.info("SkillCapture sweep: #{result.patterns.size} patterns, #{result.created.size} new, #{result.updated.size} updated")
  end
end
