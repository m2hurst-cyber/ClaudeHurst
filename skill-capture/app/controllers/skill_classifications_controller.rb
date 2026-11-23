# People set, confirm or re-infer a skill's field and apps.
class SkillClassificationsController < ApplicationController
  before_action :set_skill

  # PATCH /skills/:skill_id/classification  field_id, apps[]
  def update
    c = SkillClassification.find_or_initialize_by(skill_name: @skill.name)
    field = params[:field_id].present? ? Field.find(params[:field_id]) : nil
    c.update!(field: field, apps: Array(params[:apps]) | Capture::Classifier.observed_apps(@skill), source: "user",
              confirmed: true, confidence: nil, rationale: nil, updated_by: current_user)
    AuditLog.record("classification.set", user: current_user, subject: @skill, field: field&.path, apps: c.apps)
    redirect_back fallback_location: skill_path(@skill), notice: "Classification saved."
  end

  # POST /skills/:skill_id/classification/confirm: accept the AI's suggestion as is
  def confirm
    c = SkillClassification.for(@skill.name) || Capture::Classifier.apply!(@skill)
    c.update!(confirmed: true, updated_by: current_user)
    AuditLog.record("classification.confirmed", user: current_user, subject: @skill, field: c.field&.path)
    redirect_back fallback_location: skill_path(@skill), notice: "Classification confirmed."
  end

  # POST /skills/:skill_id/classification/reinfer: unlock and infer again
  def reinfer
    SkillClassification.for(@skill.name)&.update!(confirmed: false)
    Capture::Classifier.apply!(@skill)
    redirect_back fallback_location: skill_path(@skill), notice: "Classification re-inferred."
  end

  private

  def set_skill
    @skill = Skill.find(params[:skill_id])
    raise Pundit::NotAuthorizedError unless SkillPolicy.new(current_user, @skill).classify?
  end
end
