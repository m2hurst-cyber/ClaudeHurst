# Gate thresholds for moving skills local (sandbox) → firm → market. One row, admin-editable.
class PromotionPolicy < ApplicationRecord
  validates :initial_stage, inclusion: { in: %w[local firm] }
  validates :firm_min_trips, :firm_min_people, :market_min_days, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :firm_min_score, :market_min_score, numericality: { only_integer: true }
  validate { errors.add(:market_max_tier, "must be one of the pricing tiers") unless PricingSchedule.current.tier(market_max_tier) }

  def self.current = first || create!
end
