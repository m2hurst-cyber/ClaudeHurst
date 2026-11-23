module Api
  module V1
    module Addin
      class EventsController < BaseController
        # POST /api/v1/addin/events  { "host": "Excel", "events": [...] }
        # Events are attributed to the connected person; any actor in the payload is ignored.
        def create
          return render(json: { error: "capture is disabled" }, status: :service_unavailable) unless Capture::Config.enabled?

          source = Source.for_office_host(params.require(:host))
          events = params.require(:events)
          return render(json: { error: "events must be an array" }, status: :unprocessable_entity) unless events.is_a?(Array)

          result = Capture::Ingestor.call(source, events, actor: current_user)
          # Triggers run in the background, at most every few minutes per person, so the AI has time to judge.
          checking = result.accepted.positive? && PromptCheckJob.request(current_user)
          render json: { accepted: result.accepted, rejected: result.rejected, dropped_fields: result.dropped_fields, prompt_check: checking ? "queued" : "not_due" },
                 status: result.accepted.zero? && result.rejected.any? ? :unprocessable_entity : :accepted
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end
      end
    end
  end
end
