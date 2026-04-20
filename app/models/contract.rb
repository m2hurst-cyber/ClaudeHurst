class Contract < ApplicationRecord
  include AASM
  has_paper_trail

  PAYMENT_TERMS = %w[net_15 net_30 net_45 net_60 due_on_receipt].freeze

  belongs_to :company
  has_many :pricing_tiers, class_name: "ContractPricingTier", dependent: :destroy, inverse_of: :contract
  accepts_nested_attributes_for :pricing_tiers, allow_destroy: true, reject_if: :all_blank

  validates :number, :title, presence: true
  validates :number, uniqueness: true
  validates :payment_terms, inclusion: { in: PAYMENT_TERMS }

  before_validation :assign_number, on: :create

  aasm column: :status, whiny_transitions: false do
    state :draft, initial: true
    state :signed, :active, :expired, :terminated

    event :mark_signed do
      transitions from: :draft, to: :signed, after: :stamp_signed
    end
    event :activate do
      transitions from: :signed, to: :active
    end
    event :expire do
      transitions from: [:signed, :active], to: :expired
    end
    event :terminate do
      transitions from: [:signed, :active], to: :terminated
    end
  end

  def unit_price_cents_for(product, quantity)
    tier = pricing_tiers.where(product: product)
                       .where("min_quantity <= ?", quantity)
                       .order(min_quantity: :desc).first
    tier&.unit_price_cents
  end

  private

  def assign_number
    self.number ||= "CM-#{Date.current.year}-#{NumberSequence.next_for('contract').to_s.rjust(4, '0')}"
  end

  def stamp_signed
    update_column(:signed_at, Time.current)
  end
end
