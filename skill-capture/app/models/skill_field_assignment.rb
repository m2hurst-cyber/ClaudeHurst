class SkillFieldAssignment < ApplicationRecord
  belongs_to :skill_classification
  belongs_to :field
  validates :field_id, uniqueness: { scope: :skill_classification_id }
  validates :source, inclusion: { in: SkillClassification::SOURCES }
end
