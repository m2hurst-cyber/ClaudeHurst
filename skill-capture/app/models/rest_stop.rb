# A rest stop: a complete, restorable snapshot of a skill at a point in time (its text, workflow,
# directions, resources and fields). Taken automatically before and after every change, daily,
# when a branch is made, and on demand. Reverting to one publishes it as a new version; nothing
# is rewritten. Each one is also mirrored to disk (Capture::RestStops) for redundancy.
class RestStop < ApplicationRecord
  KINDS = %w[auto manual].freeze
  REASONS = {
    "manual" => "Saved by hand", "published" => "Published", "before_update" => "Before an update",
    "revised" => "New version", "branched" => "Branch created", "branch_point" => "Where this branch started",
    "before_revert" => "Before a revert", "reverted" => "Reverted", "promoted" => "Promoted", "directions" => "Directions changed",
    "daily" => "Daily", "restored" => "Restored from the mirror"
  }.freeze

  belongs_to :skill, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  validates :skill_name, :skill_version, :reason, :checksum, presence: true
  validates :kind, inclusion: { in: KINDS }
  validates :reason, inclusion: { in: REASONS.keys }
  validates :label, length: { maximum: 120 }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def self.checksum_for(snapshot) = Digest::SHA256.hexdigest(JSON.generate(canonical(snapshot)))
  def self.canonical(v)
    case v
    when Hash then v.keys.map(&:to_s).sort.to_h { |k| [k, canonical(v[k] || v[k.to_sym])] }
    when Array then v.map { |x| canonical(x) }
    else v
    end
  end

  def reason_label = REASONS[reason]
  def title = snapshot["title"]
  def intact? = self.class.checksum_for(snapshot) == checksum
  def directions = Array(snapshot["directions"])
  def workflow = Array(snapshot["workflow"])
end
