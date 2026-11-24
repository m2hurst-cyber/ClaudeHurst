module Api
  module V1
    module Addin
      # Claude (or another agent) working inside Office reports a run of a skill, as the signed-in person.
      class SkillRunsController < BaseController
        def create
          skill = Skill.current(params[:skill_id])
          raise ActiveRecord::RecordNotFound unless skill&.visible_to?(current_user)
          run = SkillRun.from_report(skill, params.permit(:model, :input_tokens, :output_tokens, :duration_ms, :started_at, :finished_at, :status, :version, :trial_of, :engine, :nature),
                                     agent: params[:agent].to_s.strip.presence || "Office add-in (#{current_token.host || 'Office'})", user: current_user)
          run.engine = params[:engine].to_s.presence_in(%w[ai macro person]) || "ai"
          run.cost = Capture::Models.cost(run.model, run.input_tokens, run.output_tokens)
          if run.engine == "macro" && (mr = Capture::MacroScreen.approved_for_skill(skill.name))
            mr.record_saving!(Capture::Estimator.for_step({ "title" => skill.title, "skill_name" => skill.name, "engine" => "ai" })["tokens"])
          end
          if run.save
            render json: { id: run.id, usage: Capture::Intensity.for(skill.name) }, status: :created
          else
            render json: { error: run.errors.full_messages.to_sentence }, status: :unprocessable_entity
          end
        end
      end
    end
  end
end
