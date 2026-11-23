class Skill < ApplicationRecord
  NAME_FORMAT = /\A[a-z0-9]+(-[a-z0-9]+)*\z/
  STATUSES = %w[published superseded deprecated].freeze
  # local: sandbox (authors, contributors, the area's people). firm: everyone in the firm and agents.
  # market: promoted beyond the firm (curated catalog / marketplace export).
  STAGES = %w[local firm market].freeze
  STAGE_LABELS = { "local" => "Local", "firm" => "Firm", "market" => "Market" }.freeze
  SHARED_STAGES = %w[firm market].freeze

  belongs_to :parent_skill, class_name: "Skill", optional: true
  belongs_to :published_by, class_name: "User", optional: true
  has_many :children, class_name: "Skill", foreign_key: :parent_skill_id, dependent: :nullify
  has_one :source_candidate, class_name: "SkillCandidate", dependent: :nullify

  validates :name, presence: true, length: { maximum: 64 }, format: { with: NAME_FORMAT }
  validates :version, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :name }
  validates :title, :body, presence: true
  validates :description, presence: true, length: { maximum: 1024 }
  validates :status, inclusion: { in: STATUSES }
  validates :stage, inclusion: { in: STAGES }

  scope :published, -> { where(status: "published") }
  scope :shared, -> { where(stage: SHARED_STAGES) }

  # What a person may see: firm and market for everyone; local (sandbox) skills for their
  # publisher, their contributors, people whose areas include the skill's area, and admins.
  # No user (agents on the integration API) means shared skills only.
  def self.visible_to(user)
    return shared if user.nil?
    return all if user.admin?
    local = where(stage: "local").where(
      "skills.domain = ANY(ARRAY[:areas]::varchar[]) OR skills.published_by_id = :id OR jsonb_exists(COALESCE(skills.source->'contributor_keys', '[]'::jsonb), :actor)",
      areas: user.domains.presence || [""], id: user.id, actor: user.actor_key
    )
    shared.or(local)
  end

  def visible_to?(user) = Skill.visible_to(user).exists?(id: id)
  def shared? = SHARED_STAGES.include?(stage)
  def stage_label = STAGE_LABELS[stage]
  def next_stage = { "local" => "firm", "firm" => "market" }[stage]

  # The first name in this skill's lineage: skills sharing a root are alternatives for the same job.
  def root_name = lineage.last.name

  # Current published alternatives in the same family (the skill, its branches, their branches...).
  def family
    root = root_name
    Skill.published.includes(:parent_skill).select { |s| s.root_name == root }.sort_by(&:published_at)
  end
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
