class FinishedGoodMovement < ApplicationRecord
  KINDS = %w[produce ship adjust scrap].freeze

  belongs_to :finished_good_lot
  belongs_to :user, optional: true
  belongs_to :reference, polymorphic: true, optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :quantity, presence: true, numericality: { other_than: 0 }
  validates :occurred_at, presence: true
end
