# A tax (or other playbook) situation: a question asked at intake whose "yes" adds a branch
# to the route right after the mainline step it hangs off. New situations start "proposed"
# with a branch candidate in review, and become active when that branch is published.
class Situation < ApplicationRecord
  STATUSES = %w[active proposed retired].freeze

  belongs_to :candidate, class_name: "SkillCandidate", optional: true
  belongs_to :proposed_by, class_name: "User", optional: true

  validates :key, presence: true, format: { with: /\A[a-z0-9-]+\z/ }, uniqueness: { scope: :playbook_key }
  validates :question, :after_skill, :playbook_key, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :for_playbook, ->(key) { where(playbook_key: key).where.not(status: "retired").order(:position, :id) }

  def branch = branch_skill && Skill.current(branch_skill)
  def live? = status == "active" && branch.present?
end
