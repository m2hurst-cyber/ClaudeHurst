# One vote per person per skill (by name, so it carries across versions): +1 or -1, with an optional reason.
class SkillVote < ApplicationRecord
  belongs_to :user

  validates :skill_name, presence: true
  validates :value, inclusion: { in: [-1, 1] }
  validates :user_id, uniqueness: { scope: :skill_name }
  validates :comment, length: { maximum: 1000 }

  # { name => { score:, up:, down: } }
  def self.tallies(names)
    rows = where(skill_name: names).group(:skill_name, :value).count
    Array(names).index_with do |n|
      up = rows[[n, 1]].to_i
      down = rows[[n, -1]].to_i
      { score: up - down, up: up, down: down }
    end
  end
end
