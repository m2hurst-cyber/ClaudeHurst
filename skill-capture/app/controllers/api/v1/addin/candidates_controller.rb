module Api
  module V1
    module Addin
      # Review from inside Office: list open items, read the draft, approve or reject.
      class CandidatesController < BaseController
        before_action :set_candidate, only: %i[show approve reject]

        def index
          scope = policy_scope(SkillCandidate).open.recent.limit(50)
          scope = scope.select { |c| c.reviewable_by?(current_user) } unless params[:mine] == "1"
          render json: scope.map { |c| summary(c) }
        end

        def show
          authorize @candidate
          render json: summary(@candidate).merge(
            steps: @candidate.step_labels.map { |k, l| { action: k, label: l } },
            draft_description: @candidate.draft_description, draft_body: @candidate.draft_body,
            contributors: @candidate.contributor_names, can_approve: policy(@candidate).approve?,
            url: skill_candidate_url(@candidate)
          )
        end

        def approve
          authorize @candidate
          skill = Capture::Publisher.publish!(@candidate, reviewer: current_user)
          render json: { name: skill.name, version: skill.version, url: skill_url(skill) }, status: :created
        rescue Capture::Publisher::Error, ActiveRecord::RecordInvalid => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def reject
          authorize @candidate
          @candidate.update!(status: "rejected", reviewer: current_user, reviewed_at: Time.current, review_notes: params[:notes].presence)
          AuditLog.record("skill_candidate.rejected", user: current_user, subject: @candidate, notes: @candidate.review_notes, via: "addin")
          head :no_content
        end

        private

        def set_candidate = @candidate = SkillCandidate.find(params[:id])

        def summary(c)
          { id: c.id, title: c.display_title, status: c.status, domain: c.domain, origin: c.origin,
            occurrences: c.occurrence_count, people: c.distinct_actor_count, drafted: c.drafted?, last_seen_at: c.last_seen_at }
        end
      end
    end
  end
end
