class Deal < ApplicationRecord
  include Discard::Model
  include AASM
  has_paper_trail

  monetize :amount_cents

  belongs_to :company
  belongs_to :owner, class_name: "User", optional: true
  has_many :activities, as: :subject, dependent: :destroy

  STAGES = %w[lead qualified proposal negotiation closed_won closed_lost].freeze

  validates :name, presence: true
  validates :stage, inclusion: { in: STAGES }

  aasm column: :stage, whiny_transitions: false do
    state :lead, initial: true
    state :qualified, :proposal, :negotiation, :closed_won, :closed_lost

    event :qualify do
      transitions from: [:lead], to: :qualified
    end
    event :propose do
      transitions from: [:lead, :qualified], to: :proposal
    end
    event :negotiate do
      transitions from: [:proposal, :qualified], to: :negotiation
    end
    event :win do
      transitions from: [:lead, :qualified, :proposal, :negotiation], to: :closed_won, after: :mark_closed
    end
    event :lose do
      transitions from: [:lead, :qualified, :proposal, :negotiation], to: :closed_lost, after: :mark_closed
    end
  end

  scope :open, -> { where.not(stage: %w[closed_won closed_lost]) }
  scope :won, -> { where(stage: "closed_won") }

  def open?
    !%w[closed_won closed_lost].include?(stage)
  end

  PIPELINE_PROGRESSION = %w[lead qualified proposal negotiation closed_won].freeze

  def next_stage
    idx = PIPELINE_PROGRESSION.index(stage)
    return nil if idx.nil? || idx == PIPELINE_PROGRESSION.length - 1
    PIPELINE_PROGRESSION[idx + 1]
  end

  private

  def mark_closed
    update_column(:closed_at, Time.current)
  end
end
