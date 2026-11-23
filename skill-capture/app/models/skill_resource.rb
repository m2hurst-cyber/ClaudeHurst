class SkillResource < ApplicationRecord
  belongs_to :resource
  belongs_to :added_by, class_name: "User", optional: true
  validates :skill_name, presence: true
  validates :resource_id, uniqueness: { scope: :skill_name }
end
