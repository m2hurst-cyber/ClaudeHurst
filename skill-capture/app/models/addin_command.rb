# A skill (or a whole route) sent from the map to someone's running Office add-in, or to an
# agent integration. Delivered when the add-in (or agent) next checks in; expires after a day.
class AddinCommand < ApplicationRecord
  KINDS = %w[load_skill load_route].freeze

  belongs_to :sender, class_name: "User", optional: true
  belongs_to :target_user, class_name: "User", optional: true
  belongs_to :target_source, class_name: "Source", optional: true

  validates :kind, inclusion: { in: KINDS }
  validate { errors.add(:base, "needs exactly one target") unless [target_user_id, target_source_id].compact.size == 1 }

  scope :pending, -> { where(status: "pending").where("expires_at > ?", Time.current) }
  scope :recent, -> { order(created_at: :desc) }

  before_validation { self.expires_at ||= 1.day.from_now }

  def skill_names = Array(payload["skills"])
  def target_label = target_user&.name || target_source&.name
end
