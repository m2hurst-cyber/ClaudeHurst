class ProductionRun < ApplicationRecord
  include AASM
  has_paper_trail

  belongs_to :product
  belongs_to :bom, optional: true
  belongs_to :production_line
  belongs_to :owner, class_name: "User", optional: true

  has_many :consumptions, class_name: "ProductionRunConsumption", dependent: :destroy
  has_many :finished_good_lots, dependent: :restrict_with_error
  has_many :invoices, dependent: :nullify

  validates :number, presence: true, uniqueness: true
  validates :planned_units, presence: true, numericality: { greater_than: 0 }
  validates :scheduled_start, presence: true

  before_validation :assign_number, on: :create
  before_validation :assign_batch_code, on: :create

  aasm column: :status, whiny_transitions: false do
    state :planned, initial: true
    state :released, :in_progress, :completed, :closed, :cancelled

    event :release do
      transitions from: :planned, to: :released
    end
    event :start_run do
      transitions from: :released, to: :in_progress, after: :record_actual_start
    end
    event :complete do
      transitions from: :in_progress, to: :completed, after: :record_actual_end
    end
    event :close do
      transitions from: :completed, to: :closed
    end
    event :cancel do
      transitions from: [:planned, :released], to: :cancelled
    end
  end

  scope :open, -> { where.not(status: %w[closed cancelled]) }
  scope :upcoming, -> { where(status: %w[planned released]).order(:scheduled_start) }

  private

  def assign_number
    self.number ||= "PR-#{Date.current.year}-#{NumberSequence.next_for('production_run').to_s.rjust(4, '0')}"
  end

  def assign_batch_code
    return if batch_code.present?
    self.batch_code = "B#{scheduled_start.to_date.strftime('%y%j')}-#{production_line&.code || 'X'}"
  end

  def record_actual_start
    update_column(:actual_start, Time.current)
  end

  def record_actual_end
    update_column(:actual_end, Time.current)
  end
end
