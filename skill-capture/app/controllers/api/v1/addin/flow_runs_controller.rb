module Api
  module V1
    module Addin
      # Run a flow from the add-in; finish your task and hand off to the next one.
      class FlowRunsController < BaseController
        def create
          f = Flow.find(params[:flow_id])
          raise Pundit::NotAuthorizedError unless f.visible_to?(current_user)
          render json: summary(FlowRun.start!(f, user: current_user, from: params[:from].to_i, only: params[:only].to_s.in?(%w[1 true]))), status: :created
        rescue FlowRun::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def show = render(json: summary(find))

        def complete
          r = find
          r.complete!(index: params[:step].to_i, user: current_user, note: params[:note], usage: usage_params)
          render json: summary(r)
        rescue FlowRun::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        # One part of a split task (the other parts carry on independently).
        def complete_part = act { |r| r.complete_part!(index: params[:step].to_i, part_id: params[:part], user: current_user, note: params[:note], usage: usage_params) }

        def resume = act { |r| r.resume_pause!(index: params[:step].to_i, by: current_user) }
        def hold = act { |r| r.hold!(by: current_user) }
        def release = act { |r| r.release!(by: current_user) }
        def jump = act { |r| r.jump_to!(params[:step], by: current_user) }
        def skip = act { |r| r.skip!(params[:step], by: current_user) }
        def insert = act { |r| r.insert!(after: params[:after], step: params.permit(:title, :app, :assignee, :kind, :pause_mode, :pause_minutes, :instructions).to_h, by: current_user) }

        private

        def usage_params = params[:usage]&.permit(:model, :input_tokens, :output_tokens, :duration_ms, :trial_of)

        # The approved macros for the current task, so the add-in can run them instead of calling the AI.
        def macros_for(run)
          s = run.current
          return {} unless run.running? && s
          review = Capture::MacroScreen.approved_for_step(run.flow_id, s) || Capture::MacroScreen.approved_for_skill(s["skill_name"])
          return {} unless review&.runnable_in_addin?
          units = Flow.split?(s) ? Flow.parts(s).select { |p| p["engine"] == "macro" }.map { |p| p["id"] } : (s["engine"] == "macro" ? ["step"] : [])
          units.index_with { { language: review.language, code: review.code, review_id: review.id, title: review.title } }
        end

        def act
          r = find
          yield r
          render json: summary(r)
        rescue FlowRun::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end

        def find
          r = FlowRun.find(params[:id])
          raise Pundit::NotAuthorizedError unless r.user_id == current_user.id || r.steps.any? { |s| s["assignee"] == "user:#{current_user.id}" }
          r
        end

        def summary(r)
          Api::V1::FlowRunsController.summary(r).merge(url: flow_run_url(r), markdown: Capture::LlmMarkdown.run(r), macros: macros_for(r), mine: r.running? && r.doer?(user: current_user), owner: r.owner?(current_user))
        end
      end
    end
  end
end
