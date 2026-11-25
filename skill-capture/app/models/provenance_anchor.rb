# A commitment to everything in the chain up to a point: the Merkle root of the entries in
# the window plus the chain tip. Once an anchor is published somewhere we do not control,
# the history beneath it cannot be rewritten without that being visible.
class ProvenanceAnchor < ApplicationRecord
  validates :on_date, :from_sequence, :to_sequence, :root_hash, :tip_hash, presence: true
  validates :on_date, uniqueness: true

  scope :recent, -> { order(on_date: :desc) }

  def entries = ProvenanceEntry.where(sequence: from_sequence..to_sequence).chronological

  # Recompute from the entries still in the database. False means something beneath
  # this anchor has changed since it was published.
  def holds? = Capture::Canonical.merkle_root(entries.pluck(:entry_hash)) == root_hash

  def to_h
    { "on_date" => on_date.iso8601, "from" => from_sequence, "to" => to_sequence,
      "entries" => entry_count, "root" => root_hash, "tip" => tip_hash }
  end
end
