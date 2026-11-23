module Api
  module V1
    class EventsController < BaseController
      # POST /api/v1/events  { "events": [ {...}, ... ] }
      def create
        return render(json: { error: "capture is disabled" }, status: :service_unavailable) unless Capture::Config.enabled?

        events = params.require(:events)
        return render(json: { error: "events must be an array" }, status: :unprocessable_entity) unless events.is_a?(Array)

        result = Capture::Ingestor.call(current_source, events)
        check_ingest_rate!
        status = result.accepted.zero? && result.rejected.any? ? :unprocessable_entity : :accepted
        render json: { accepted: result.accepted, rejected: result.rejected, dropped_fields: result.dropped_fields }, status: status
      rescue ArgumentError => e
        render json: { error: e.message }, status: :content_too_large
      end

      private

      def check_ingest_rate!
        count = current_source.usage_events.where("created_at > ?", 1.hour.ago).count
        return if count <= Capture::Config.ingest_alert_threshold
        return if AuditLog.where(action: "capture.alert", source: current_source).where("created_at > ?", 1.hour.ago).exists?

        AuditLog.record("capture.alert", source: current_source, reason: "ingest_rate", count_last_hour: count)
        User.active.where(role: "admin").find_each do |admin|
          Notification.create!(user: admin, kind: "alert", title: "Unusual event volume from #{current_source.name}: #{count} in the last hour")
        end
      end
    end
  end
end
