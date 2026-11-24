# A worksheet captured from Excel and turned into a draft skill:
#   observed       labels and formulas by cell (numbers are never sent)
#   interpretation what the sheet is attempting, its shape, inputs, dependencies, risks
#   inventory      every formula pattern, matched to the provider's command library or proposed as new
#   files          STRUCTURE.md, FORMULAS.md, blueprint.json and the drafted SKILL.md
class WorksheetCapture < ApplicationRecord
  belongs_to :user
  belongs_to :candidate, class_name: "SkillCandidate", optional: true

  validates :sheet_name, presence: true

  def visible_to?(u) = u.present? && (u.id == user_id || u.admin? || (candidate && candidate.reviewable_by?(u)))

  def files
    {
      "STRUCTURE.md" => structure_md, "FORMULAS.md" => formulas_md,
      "blueprint.json" => JSON.pretty_generate(blueprint), "SKILL.md" => skill_md
    }.compact
  end
end
