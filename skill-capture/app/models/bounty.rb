class Bounty < ApplicationRecord
  STATUSES = %w[open measuring awaiting_approval paid closed].freeze
  ACTIVE = %w[open measuring awaiting_approval].freeze

  belongs_to :solver, class_name: "User", optional: true
  belongs_to :approved_by, class_name: "User", optional: true
  has_many :credit_entries, dependent: :nullify

  validates :skill_name, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: ACTIVE) }

  def self.active_for(name) = active.find_by(skill_name: name)

  def skill = Skill.current(skill_name)
end
