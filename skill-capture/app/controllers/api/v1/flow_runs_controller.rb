module Api
  module V1
    # Agents in a flow: a flow task arrives through GET /api/v1/commands (kind "flow_task"); when the agent
    # has finished, it completes the step and the run hands off to the next task:
    #   POST /api/v1/flow_runs/:id/complete?step=3
    #   { "note": "what was done / where the output is", "usage": { "model": "...", "input_tokens": 0, "output_tokens": 0, "duration_ms": 0 } }
    class FlowRunsController < BaseController
      def show
        run = FlowRun.find(params[:id])
        raise ActiveRecord::RecordNotFound unless run.steps.any? { |s| s["assignee"] == "agent:#{current_source.id}" }
        render json: Api::V1::FlowRunsController.summary(run)
      end

      def complete
        run = FlowRun.find(params[:id])
        run.complete!(index: params[:step].to_i, source: current_source, note: params[:note], usage: params[:usage]&.permit(:model, :input_tokens, :output_tokens, :duration_ms))
        render json: self.class.summary(run)
      rescue FlowRun::Error => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def self.summary(run)
        { id: run.id, flow: run.flow.name, status: run.status, current_index: run.current_index,
          steps: run.steps.each_with_index.map { |s, i| s.slice("title", "app", "state", "note", "by", "usage", "skill_name", "kind", "pause_mode", "pause_minutes", "resume_at").merge("index" => i, "assignee" => Flow.assignee_label(s["assignee"], owner: run.user)) } }
      end
    end
  end
end
