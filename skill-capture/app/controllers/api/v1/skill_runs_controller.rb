module Api
  module V1
    # Agents report each run of a skill: POST /api/v1/skills/:skill_id/runs
    #   { "model": "...", "input_tokens": 1200, "output_tokens": 800, "duration_ms": 42000, "status": "succeeded" }
    class SkillRunsController < BaseController
      def create
        skill = Skill.current(params[:skill_id]) or raise ActiveRecord::RecordNotFound
        run = SkillRun.from_report(skill, params.permit(:model, :input_tokens, :output_tokens, :duration_ms, :started_at, :finished_at, :status, :version),
                                   agent: params[:agent].to_s.strip.presence || current_source.name, source: current_source)
        if run.save
          render json: { id: run.id, usage: Capture::Intensity.for(skill.name) }, status: :created
        else
          render json: { error: run.errors.full_messages.to_sentence }, status: :unprocessable_entity
        end
      end
    end
  end
end
