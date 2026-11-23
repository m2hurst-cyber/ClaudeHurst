# People set, confirm or re-infer a skill's fields and apps, and can grow the taxonomy as they go.
class SkillClassificationsController < ApplicationController
  before_action :set_skill

  # PATCH /skills/:skill_id/classification
  #   field_ids[] (kept, in order) · add_field_id · new_field_name + new_field_parent_id · apps[]
  def update
    c = SkillClassification.find_or_initialize_by(skill_name: @skill.name)
    ids = Array(params[:field_ids]).reject(&:blank?).map(&:to_i)
    ids << params[:add_field_id].to_i if params[:add_field_id].present?
    if params[:new_field_name].present?
      parent = params[:new_field_parent_id].present? ? Field.find(params[:new_field_parent_id]) : nil
      created = Field.find_or_create_by!(path: [parent&.path, params[:new_field_name].to_s.parameterize].compact.join("/")) do |f|
        f.name = params[:new_field_name].to_s.strip.first(60)
        f.parent = parent
        f.created_by = current_user
        f.position = (parent ? parent.children.maximum(:position) : Field.roots.maximum(:position)).to_i + 1
      end
      AuditLog.record("field.created", user: current_user, subject: created, path: created.path, via: "skill") if created.previously_new_record?
      ids << created.id
    end
    fields = Field.where(id: ids.uniq).index_by(&:id).values_at(*ids.uniq).compact
    c.update!(apps: Array(params[:apps]) | Capture::Classifier.observed_apps(@skill), source: "user",
              confirmed: true, confidence: nil, rationale: nil, updated_by: current_user)
    c.set_fields!(fields, source: "user")
    AuditLog.record("classification.set", user: current_user, subject: @skill, fields: fields.map(&:path), apps: c.apps)
    redirect_back fallback_location: skill_path(@skill), notice: "Classification saved."
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: skill_path(@skill), alert: e.message
  end

  # POST /skills/:skill_id/classification/confirm: accept the inference as is
  def confirm
    c = SkillClassification.for(@skill.name) || Capture::Classifier.apply!(@skill)
    c.update!(confirmed: true, updated_by: current_user)
    AuditLog.record("classification.confirmed", user: current_user, subject: @skill, fields: c.field_paths)
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
