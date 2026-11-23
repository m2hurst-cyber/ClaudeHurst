# Attach library resources to a skill (or detach them).
class SkillResourcesController < ApplicationController
  before_action :set_skill

  def create
    r = Resource.find(params[:resource_id])
    raise Pundit::NotAuthorizedError unless r.visible_to?(current_user)
    SkillResource.find_or_create_by!(skill_name: @skill.name, resource: r) { |sr| sr.added_by = current_user }
    AuditLog.record("skill_resource.attached", user: current_user, subject: @skill, resource: r.key)
    redirect_back fallback_location: skill_path(@skill), notice: "Attached #{r.name}."
  end

  def destroy
    SkillResource.where(skill_name: @skill.name, resource_id: params[:id]).delete_all
    redirect_back fallback_location: skill_path(@skill), notice: "Detached."
  end

  private

  def set_skill
    @skill = Skill.find(params[:skill_id])
    raise Pundit::NotAuthorizedError unless SkillPolicy.new(current_user, @skill).classify?
  end
end
