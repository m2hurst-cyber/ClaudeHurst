class Promotion < ApplicationRecord
  STATUSES = %w[open approved rejected withdrawn].freeze

  belongs_to :requested_by, class_name: "User", optional: true
  belongs_to :decided_by, class_name: "User", optional: true

  validates :skill_name, :from_stage, :to_stage, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :to_stage, inclusion: { in: %w[firm market] }

  scope :open, -> { where(status: "open") }
  scope :recent, -> { order(created_at: :desc) }

  def skill = Skill.current(skill_name)
end
