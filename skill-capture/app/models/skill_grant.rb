# A skill sent person to person: the recipient can see and use it at its current stage (a local skill stays
# local; nothing moves up a level). One grant per person and skill; later versions stay visible.
class SkillGrant < ApplicationRecord
  belongs_to :user
  belongs_to :transfer, class_name: "SkillTransfer", optional: true
  belongs_to :granted_by, class_name: "User", optional: true
  validates :skill_name, presence: true, uniqueness: { scope: :user_id }
end
