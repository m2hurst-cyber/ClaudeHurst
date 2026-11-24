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

      # An agent finishing its part of a split task.
      def complete_part
        run = FlowRun.find(params[:id])
        run.complete_part!(index: params[:step].to_i, part_id: params[:part], source: current_source, note: params[:note], usage: usage_params)
        render json: self.class.summary(run)
      rescue FlowRun::Error => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def complete
        run = FlowRun.find(params[:id])
        run.complete!(index: params[:step].to_i, source: current_source, note: params[:note], usage: usage_params)
        render json: self.class.summary(run)
      rescue FlowRun::Error => e
        render json: { error: e.message }, status: :unprocessable_entity
      end

      def usage_params = params[:usage]&.permit(:model, :input_tokens, :output_tokens, :duration_ms, :trial_of)

      def self.summary(run)
        t = run.tally
        { id: run.id, flow: run.flow.name, status: run.status, current_index: run.current_index,
          budget: { estimated_tokens: t.dig("estimate", "tokens"), estimated_cost: t.dig("estimate", "cost"), estimated_seconds: t.dig("estimate", "seconds"),
                    spent_tokens: t.dig("spent", "tokens"), spent_cost: t.dig("spent", "cost"),
                    remaining_tokens: t.dig("remaining", "tokens"), projected_cost: t.dig("projected", "cost") },
          steps: run.steps.each_with_index.map do |s, i|
            s.slice("title", "app", "state", "note", "by", "usage", "skill_name", "kind", "pause_mode", "pause_minutes", "resume_at",
                    "nature", "complexity", "engine", "model")
             .merge("index" => i, "assignee" => Flow.assignee_label(s["assignee"], owner: run.user),
                    "estimate" => run.estimate.dig("steps", i)&.slice("tokens", "cost", "seconds", "basis", "model", "engine"),
                    "parts" => Flow.parts(s).map { |p| p.slice("id", "title", "engine", "model", "state", "by", "note", "usage").merge("assignee" => Flow.assignee_label(p["assignee"], owner: run.user)) }.presence)
             .compact
          end }
      end
    end
  end
end
