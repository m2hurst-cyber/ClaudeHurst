# Daily: a rest stop for every published skill that changed, then a redundancy check of every rest stop.
class RestStopSweepJob < ApplicationJob
  queue_as :default

  def perform
    made = Protocol.for("rest_stop").then { |p| p.enabled && p["daily"] } ? Capture::RestStops.sweep! : 0
    report = Capture::RestStops.verify!
    AuditLog.record("rest_stops.swept", created: made, **report.symbolize_keys) if made.positive? || report.except(:checked).values.any?(&:positive?)
    Rails.logger.info("Rest stops: #{made} new; verify #{report.inspect}")
  end
end
