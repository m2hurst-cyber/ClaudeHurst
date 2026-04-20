class Payment < ApplicationRecord
  METHODS = %w[ach check wire cash card].freeze

  monetize :amount_cents

  belongs_to :invoice

  validates :amount_cents, numericality: { greater_than: 0 }
  validates :received_on, presence: true
  validates :method, inclusion: { in: METHODS }

  after_commit :apply_to_invoice

  private

  def apply_to_invoice
    invoice.apply_payments!
  end
end
