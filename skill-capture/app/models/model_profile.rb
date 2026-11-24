# A model a task can run on, and what it costs. "macro" is the zero-token engine: deterministic Office
# script instead of an AI call. Prices are credits per 1M tokens; edit them to match your contract.
class ModelProfile < ApplicationRecord
  TIERS = %w[macro small standard deep].freeze
  TIER_RANK = TIERS.each_with_index.to_h.freeze

  validates :key, :name, presence: true, uniqueness: { scope: [] , allow_blank: true }
  validates :tier, inclusion: { in: TIERS }
  validates :input_cost, :output_cost, numericality: { greater_than_or_equal_to: 0 }
  validates :tokens_per_second, numericality: { only_integer: true, greater_than: 0 }

  scope :live, -> { where(active: true).order(:position, :key) }

  def self.for(key) = key.present? ? find_by(key: key) : nil
  def self.cheapest_in(tier) = live.where(tier: tier).min_by { |m| m.cost_for(1000, 500) }
  def macro? = tier == "macro"
  def rank = TIER_RANK[tier].to_i

  # Credits for a run of this size.
  def cost_for(input_tokens, output_tokens)
    ((input_cost.to_d * input_tokens.to_i + output_cost.to_d * output_tokens.to_i) / 1_000_000).round(4)
  end
end
