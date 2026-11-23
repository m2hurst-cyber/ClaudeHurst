module Api
  module V1
    module Addin
      # A procedure recorded in the task pane: the expert demonstrates the task once,
      # names it, and submits it. It enters the same review queue as detected workflows.
      #
      # POST /api/v1/addin/procedures
      #   { "host": "Excel", "title": "...", "domain": "finance", "description": "...",
      #     "steps": [ { "action": "excel.data.sorted", "label": "Sort data" },
      #                { "action": "excel.step:check-totals", "label": "Check totals match the bank statement" } ] }
      class ProceduresController < BaseController
        MAX_STEPS = 40

        def create
          title = params[:title].to_s.squish.first(200)
          steps = Array(params[:steps]).first(MAX_STEPS).filter_map do |s|
            s = s.respond_to?(:permit) ? s.permit(:action, :label) : s
            key = s[:action].to_s
            label = s[:label].to_s.squish.first(200)
            next unless key.match?(Capture::Ingestor::ACTION_FORMAT) && label.present?
            [key, label]
          end
          if title.blank? || steps.empty?
            return render(json: { error: "a title and at least one step are required" }, status: :unprocessable_entity)
          end

          source = Source.for_office_host(params.require(:host))
          steps.each do |key, label|
            ActionDefinition.find_or_create_by!(key: key) { |d| d.label = label; d.source = source }
          end
          keys = steps.map(&:first)
          candidate = SkillCandidate.create!(
            signature: "procedure:#{SecureRandom.hex(8)}", steps: keys, origin: "manual",
            domain: params[:domain].to_s.strip.downcase.presence || current_user.domains.first,
            draft_title: title, draft_description: params[:description].to_s.squish.first(1024).presence,
            requested_by: current_user, occurrence_count: 1, distinct_actor_count: 1,
            contributors: [{ "key" => current_user.actor_key, "name" => current_user.name }],
            first_seen_at: Time.current, last_seen_at: Time.current
          )
          AuditLog.record("skill_candidate.recorded", user: current_user, subject: candidate, host: source.kind, steps: keys.size)
          candidate.notify_reviewers!("Procedure recorded by #{current_user.name}: #{title}")
          # The template draft is instant; a Claude draft runs in the background.
          Capture::Config.llm_enabled? ? SkillDraftJob.perform_later(candidate.id) : Capture::DraftGenerator.call(candidate)
          render json: { id: candidate.id, url: skill_candidate_url(candidate) }, status: :created
        rescue ArgumentError => e
          render json: { error: e.message }, status: :unprocessable_entity
        end
      end
    end
  end
end
