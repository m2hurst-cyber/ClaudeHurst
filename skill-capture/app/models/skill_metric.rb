class SkillMetric < ApplicationRecord
  validates :name, presence: true, uniqueness: true

  def self.for(name) = find_by(name: name)
  def priced? = tier.present?
end
