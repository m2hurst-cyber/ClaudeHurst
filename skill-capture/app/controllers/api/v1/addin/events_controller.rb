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
          prompts = result.accepted.positive? ? raise_prompts : []
          render json: { accepted: result.accepted, rejected: result.rejected, dropped_fields: result.dropped_fields, prompts: prompts },
                 status: result.accepted.zero? && result.rejected.any? ? :unprocessable_entity : :accepted
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        private

        # Triggers run as the person works: a new save / extend / branch prompt comes back with the response.
        def raise_prompts
          key = "prompter:user:#{current_user.id}"
          return [] if Rails.cache.read(key) # at most once a minute per person
          Rails.cache.write(key, true, expires_in: 1.minute)
          Capture::Prompter.call(current_user).map(&:to_api)
        rescue => e
          raise if Rails.env.test?
          Rails.logger.warn("Prompts failed for user #{current_user.id}: #{e.class}: #{e.message}")
          []
        end
      end
    end
  end
end
