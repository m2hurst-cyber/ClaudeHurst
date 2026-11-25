# One link in the provenance chain: a statement about a skill at a moment, committed to
# the statement before it. Append-only — never updated, never deleted. Verification walks
# the chain and recomputes every hash, so a row edited directly in the database is caught.
class ProvenanceEntry < ApplicationRecord
  GENESIS = ("0" * 64).freeze

  EVENTS = %w[
    skill.published skill.revised skill.branched skill.promoted skill.retired
    skill.transferred attestation.recorded anchor.published
  ].freeze

  validates :sequence, :prev_hash, :entry_hash, :event, :occurred_at, presence: true
  validates :entry_hash, uniqueness: true
  validates :sequence, uniqueness: true

  scope :chronological, -> { order(:sequence) }
  scope :for_skill, ->(name) { where(skill_name: name).chronological }

  # The bytes this entry's hash is taken over. Everything that matters is in here;
  # nothing that is not in here is protected.
  def body
    { "sequence" => sequence, "prev" => prev_hash, "event" => event, "skill" => skill_name,
      "version" => skill_version, "content" => content_hash, "actor" => actor_key,
      "at" => occurred_at.utc.iso8601, "payload" => payload }
  end

  def computed_hash = Capture::Canonical.digest(body)
  def intact? = computed_hash == entry_hash
end
