# Save / extend / branch prompts for the signed-in person (also shown in the Office add-in).
class PromptsController < ApplicationController
  def index
    @live = current_user.skill_prompts.live.to_a
    @answered = current_user.skill_prompts.where(status: %w[accepted dismissed snoozed]).where.not(id: @live.map(&:id))
                            .order(responded_at: :desc).limit(15).to_a
  end

  def respond
    prompt = current_user.skill_prompts.find(params[:id])
    candidate = Capture::Prompter.respond!(prompt, choice: params[:choice].to_s, user: current_user,
                                           title: params[:title], description: params[:description])
    if candidate
      redirect_to skill_candidate_path(candidate), notice: "Sent for review. A reviewer for #{candidate.domain || 'the area'} has been notified."
    else
      redirect_to prompts_path, notice: params[:choice] == "snooze" ? "Snoozed." : "Dismissed. We won't ask about this again."
    end
  rescue Capture::Prompter::Error => e
    redirect_to prompts_path, alert: e.message
  end
end
