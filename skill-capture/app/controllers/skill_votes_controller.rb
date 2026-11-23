class SkillVotesController < ApplicationController
  # PUT /skills/:skill_id/vote  value=1|-1|0 (0 clears your vote)
  def update
    skill = Skill.find(params[:skill_id])
    authorize skill, :vote?
    Capture::Voting.cast!(current_user, skill, params[:value], comment: params[:comment])
    redirect_back fallback_location: skill_path(skill), notice: params[:value].to_i.zero? ? "Vote removed." : "Thanks, your vote is in."
  rescue Capture::Voting::Error => e
    redirect_back fallback_location: skill_path(skill), alert: e.message
  end
end
