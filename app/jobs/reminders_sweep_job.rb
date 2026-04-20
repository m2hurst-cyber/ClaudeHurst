class RemindersSweepJob < ApplicationJob
  queue_as :default

  def perform
    Reminder.due.find_each do |r|
      begin
        r.fire!
      rescue => e
        Rails.logger.error("Reminder ##{r.id} failed: #{e.class}: #{e.message}")
        AuditLogger.record(user: r.user, action: "reminder.error", subject: r, metadata: { error: e.message })
      end
    end
  end
end
