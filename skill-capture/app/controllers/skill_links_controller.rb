# Reviewers can draw a road by hand: "after this skill, people usually do that one".
class SkillLinksController < ApplicationController
  before_action :set_skill

  def create
    authorize @skill, :update?
    to = Skill.current(params[:to].to_s)
    return redirect_to(@skill, alert: "Pick a published skill.") unless to
    link = SkillLink.find_or_initialize_by(from_node: @skill.name, to_node: to.name, origin: "manual")
    link.created_by ||= current_user
    if link.save
      AuditLog.record("skill_link.created", user: current_user, subject: @skill, from: @skill.name, to: to.name)
      redirect_to @skill, notice: "Linked: after “#{@skill.title}” comes “#{to.title}”."
    else
      redirect_to @skill, alert: link.errors.full_messages.to_sentence
    end
  end

  def destroy
    authorize @skill, :update?
    link = SkillLink.manual.find_by!(from_node: @skill.name, to_node: params[:id])
    link.destroy!
    AuditLog.record("skill_link.removed", user: current_user, subject: @skill, from: link.from_node, to: link.to_node)
    redirect_to @skill, notice: "Link removed."
  end

  private

  def set_skill = @skill = Skill.find(params[:skill_id])
end
