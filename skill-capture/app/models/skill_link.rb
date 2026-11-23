class SkillLink < ApplicationRecord
  ORIGINS = %w[observed manual].freeze

  belongs_to :created_by, class_name: "User", optional: true

  validates :from_node, :to_node, presence: true
  validates :origin, inclusion: { in: ORIGINS }
  validate { errors.add(:to_node, "can't be the same skill") if from_node == to_node }

  scope :observed, -> { where(origin: "observed") }
  scope :manual, -> { where(origin: "manual") }

  def self.candidate_key(candidate) = "candidate:#{candidate.id}"

  # Next/previous skills for a skill name, merged across origins, busiest first.
  def self.neighbours(name, direction: :next)
    own, other = direction == :next ? %i[from_node to_node] : %i[to_node from_node]
    where(own => name).where.not(other => nil).group(other).pluck(other, Arel.sql("SUM(traffic)"), Arel.sql("BOOL_OR(origin = 'manual')"))
      .reject { |k, *| k.start_with?("candidate:") }
      .map { |k, traffic, manual| { name: k, traffic: traffic.to_i, manual: manual } }
      .sort_by { |h| [-h[:traffic], h[:manual] ? 0 : 1, h[:name]] }
  end
end
