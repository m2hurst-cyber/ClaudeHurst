class ContractPricingTier < ApplicationRecord
  monetize :unit_price_cents

  belongs_to :contract, inverse_of: :pricing_tiers
  belongs_to :product

  validates :min_quantity, numericality: { greater_than: 0 }
  validates :unit_price_cents, numericality: { greater_than_or_equal_to: 0 }
end
