class Activity < ApplicationRecord
  KINDS = %w[call email note meeting document_sent stage_change system].freeze

  belongs_to :subject, polymorphic: true
  belongs_to :user, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :occurred_at, presence: true

  scope :recent, -> { order(occurred_at: :desc) }
end
