# Written agent directions for a road, intersection or handoff on the route map.
# Places without written directions get a generated scaffold (Capture::Directions).
class Waypoint < ApplicationRecord
  KINDS = %w[road junction handoff].freeze
  KIND_LABELS = { "road" => "Road", "junction" => "Intersection", "handoff" => "Handoff" }.freeze

  belongs_to :updated_by, class_name: "User", optional: true
  has_many :revisions, -> { order(version: :desc) }, class_name: "WaypointRevision", dependent: :delete_all

  validates :key, presence: true, uniqueness: true
  validates :kind, inclusion: { in: KINDS }
  validates :title, :body, :from_name, presence: true
  validates :to_name, presence: true, if: -> { kind == "handoff" }
  validates :body, length: { maximum: 50_000 }

  def self.key_for(kind, from, to = nil)
    case kind
    when "road", "junction" then "#{kind}:#{from}"
    when "handoff" then "handoff:#{from}>#{to}"
    else raise ArgumentError, "unknown kind #{kind.inspect}"
    end
  end

  # "road:x" → ["road", "x", nil]; "handoff:a>b" → ["handoff", "a", "b"]
  def self.parse_key(key)
    kind, rest = key.to_s.split(":", 2)
    return nil unless KINDS.include?(kind) && rest.present?
    from, to = kind == "handoff" ? rest.split(">", 2) : [rest, nil]
    return nil if from.blank? || (kind == "handoff" && to.blank?)
    [kind, from, to]
  end

  # Full-text over title and body (indexed), plus exact tag matches.
  def self.text_search(q)
    where("to_tsvector('english', coalesce(title, '') || ' ' || coalesce(body, '')) @@ websearch_to_tsquery('english', :q) OR :tag = ANY(tags)",
          q: q, tag: q.to_s.downcase.strip)
  end
end
