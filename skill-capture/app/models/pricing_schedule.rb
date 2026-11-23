# The demand schedule: price per trip rises with congestion, tier by tier.
class PricingSchedule < ApplicationRecord
  DEFAULT_TIERS = [
    { "key" => "free", "label" => "Free-flowing", "min_index" => 0.0, "multiplier" => 1.0 },
    { "key" => "slow", "label" => "Slow", "min_index" => 1.25, "multiplier" => 1.5 },
    { "key" => "heavy", "label" => "Heavy", "min_index" => 1.75, "multiplier" => 2.5 },
    { "key" => "jammed", "label" => "Jammed", "min_index" => 3.0, "multiplier" => 4.0 }
  ].freeze

  validates :currency, :base_price, :window_days, :min_trips, :measure_min_trips, :measure_max_days, presence: true
  validates :base_price, numericality: { greater_than_or_equal_to: 0 }
  validates :pool_share, numericality: { in: 0..1 }
  validates :window_days, :min_trips, :measure_min_trips, :measure_max_days, numericality: { only_integer: true, greater_than: 0 }
  validate :tiers_are_a_schedule

  def self.current = first || create!(tiers: DEFAULT_TIERS)

  def sorted_tiers = tiers.sort_by { |t| t["min_index"].to_f }

  def tier_for(index)
    return nil if index.nil?
    sorted_tiers.reverse.find { |t| index >= t["min_index"].to_f } || sorted_tiers.first
  end

  def tier(key) = tiers.find { |t| t["key"] == key }
  def rank(key) = sorted_tiers.index { |t| t["key"] == key }

  def price_for(index)
    t = tier_for(index)
    t && (base_price * t["multiplier"].to_d).round(2)
  end

  def premium_for(index) = [price_for(index).to_d - base_price, 0].max

  # Bounties open at the bounty tier or anything worse.
  def bounty_worthy?(tier_key) = tier_key.present? && rank(tier_key).to_i >= rank(bounty_tier).to_i

  private

  def tiers_are_a_schedule
    list = Array(tiers)
    return errors.add(:tiers, "need at least two tiers") if list.size < 2
    keys = list.map { |t| t["key"] }
    errors.add(:tiers, "keys must be unique") if keys.uniq.size != keys.size
    sorted = list.sort_by { |t| t["min_index"].to_f }
    errors.add(:tiers, "the first tier must start at 0") unless sorted.first["min_index"].to_f.zero?
    mults = sorted.map { |t| t["multiplier"].to_f }
    errors.add(:tiers, "multipliers must not fall as congestion rises") unless mults.each_cons(2).all? { |a, b| b >= a }
    errors.add(:bounty_tier, "must be one of the tiers") unless keys.include?(bounty_tier)
  end
end
