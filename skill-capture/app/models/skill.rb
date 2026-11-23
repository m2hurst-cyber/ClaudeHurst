class Skill < ApplicationRecord
  NAME_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
  STATUSES = %w[published superseded deprecated].freeze

  belongs_to :parent_skill, class_name: "Skill", optional: true
  belongs_to :published_by, class_name: "User", optional: true
  has_many :children, class_name: "Skill", foreign_key: :parent_skill_id, dependent: :nullify
  has_one :source_candidate, class_name: "SkillCandidate", dependent: :nullify

  validates :name, presence: true, length: { maximum: 64 }, format: { with: NAME_FORMAT }
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :name }
  validates :title, :body, presence: true
  validates :description, presence: true, length: { maximum: 1024 }
  validates :status, inclusion: { in: STATUSES }

  scope :published, -> { where(status: "published") }
  scope :recent, -> { order(published_at: :desc, id: :desc) }

  def self.search(q)
    return all if q.blank?
    term = "%#{sanitize_sql_like(q)}%"
    where("name ILIKE :t OR title ILIKE :t OR description ILIKE :t OR :raw = ANY(tags)", t: term, raw: q.to_s.downcase)
  end

  def self.current(name) = published.where(name: name).order(version: :desc).first

  def versions = Skill.where(name: name).order(version: :desc)

  # Walks parent links back to the root (revisions and forks).
  def lineage
    chain = []
    node = self
    while node && chain.size < 50
      chain << node
      node = node.parent_skill
    end
    chain
  end

  def to_skill_md = Capture::SkillFile.render(self)
end
