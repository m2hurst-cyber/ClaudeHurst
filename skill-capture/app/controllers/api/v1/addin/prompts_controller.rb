module Api
  module V1
    module Addin
      # Save / extend / branch prompts for the connected person.
      #   GET  /api/v1/addin/prompts
      #   POST /api/v1/addin/prompts/:id/respond  { choice: save|extend|branch|snooze|dismiss, title?, description? }
      class PromptsController < BaseController
        def index = render(json: current_user.skill_prompts.live.limit(5).map(&:to_api))

        def respond
          prompt = current_user.skill_prompts.find(params[:id])
          c = Capture::Prompter.respond!(prompt, choice: params[:choice].to_s, user: current_user, title: params[:title], description: params[:description])
          render json: c ? { status: "accepted", candidate: { id: c.id, title: c.draft_title, name: c.draft_name, url: skill_candidate_url(c) } } : { status: prompt.reload.status }
        rescue Capture::Prompter::Error => e
          render json: { error: e.message }, status: :unprocessable_entity
        end
      end
    end
  end
end
