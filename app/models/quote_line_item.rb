class QuoteLineItem < ApplicationRecord
  monetize :unit_price_cents

  belongs_to :quote, inverse_of: :line_items
  belongs_to :product, optional: true

  validates :description, presence: true
  validates :quantity, numericality: { greater_than: 0 }

  def line_total_cents
    (quantity * unit_price_cents * (1 + tax_rate)).round
  end
end
