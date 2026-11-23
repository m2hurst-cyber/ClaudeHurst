module Api
  module V1
    # Agents can read the rest stops of shared skills (to pin to a known-good state or compare).
    #   GET /api/v1/skills/:skill_id/rest_stops      list
    #   GET /api/v1/rest_stops/:id                    one, with its snapshot
    class RestStopsController < BaseController
      def index
        skill = Skill.current(params[:skill_id])
        raise ActiveRecord::RecordNotFound unless skill&.shared?
        render json: RestStop.where(skill_name: skill.name).recent.limit(100).map { |s| summary(s) }
      end

      def show
        stop = RestStop.find(params[:id])
        raise ActiveRecord::RecordNotFound unless Skill.current(stop.skill_name)&.shared?
        render json: summary(stop).merge(snapshot: stop.snapshot)
      end

      private

      def summary(s)
        { id: s.id, skill: s.skill_name, version: s.skill_version, kind: s.kind, reason: s.reason, label: s.label,
          pinned: s.pinned, checksum: s.checksum, created_at: s.created_at.iso8601 }
      end
    end
  end
end
