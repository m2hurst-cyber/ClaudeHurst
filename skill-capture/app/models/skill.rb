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

  # Viewing levels, from closest to widest: what I wrote or worked on, my department's, the firm's,
  # my industry's, and everyone's. Always intersected with visible_to (sandbox rules still apply).
  LEVELS = %w[mine received department firm industry global].freeze
  LEVEL_LABELS = { "mine" => "Mine", "received" => "Sent to me", "department" => "Department", "firm" => "Firm", "industry" => "Industry", "global" => "Global" }.freeze
  MARKET_AUDIENCES = %w[industry global].freeze
  validates :market_audience, inclusion: { in: MARKET_AUDIENCES }

  scope :published, -> { where(status: "published") }
  scope :shared, -> { where(stage: SHARED_STAGES) }

  # What a person may see: firm and market for everyone; local (sandbox) skills for their
  # publisher, their contributors, people whose areas include the skill's area, and admins.
  # No user (agents on the integration API) means shared skills only.
  def self.visible_to(user)
    return shared if user.nil?
    return all if user.admin?
    local = where(stage: "local").where(
      "skills.domain = ANY(ARRAY[:areas]::varchar[]) OR skills.published_by_id = :id OR jsonb_exists(COALESCE(skills.source->'contributor_keys', '[]'::jsonb), :actor) " \
      "OR skills.name IN (SELECT skill_name FROM skill_grants WHERE skill_grants.user_id = :id)",
      areas: user.domains.presence || [""], id: user.id, actor: user.actor_key
    )
    shared.or(local)
  end

  # Skills these people published, contributed to (captured from their work) or asked for.
  def self.authored_by(users)
    ids = Array(users).map { |u| u.is_a?(User) ? u.id : u }.uniq
    return none if ids.empty?
    keys = ids.map { |i| "user:#{i}" }
    requested = SkillCandidate.where(requested_by_id: ids).where.not(skill_id: nil).select(:skill_id)
    where(published_by_id: ids)
      .or(where("jsonb_exists_any(COALESCE(skills.source->'contributor_keys', '[]'::jsonb), ARRAY[:keys]::text[])", keys: keys))
      .or(where(id: requested))
  end

  def self.at_level(level, user)
    case level
    when "mine" then authored_by([user])
      when "received" then where(name: SkillGrant.where(user: user).select(:skill_name))
    when "department" then authored_by(user.department_colleagues)
    when "firm" then where(stage: "firm")
    when "industry" then where(stage: "market", market_audience: "industry")
    when "global" then where(stage: "market", market_audience: "global")
    else all
    end
  end

  # Filters by classification: an app ("Excel") and/or a field path including its subfields.
  def self.classified_as(app: nil, field: nil)
    scope = all
    if app.present?
      scope = scope.where(name: SkillClassification.where(":app = ANY(apps)", app: app).select(:skill_name))
    end
    if field.present?
      ids = Field.where("path = :p OR path LIKE :c", p: field, c: "#{sanitize_sql_like(field)}/%").select(:id)
      scope = scope.where(name: SkillClassification.where(id: SkillFieldAssignment.where(field_id: ids).select(:skill_classification_id)).select(:skill_name))
    end
    scope
  end

  def classification = SkillClassification.for(name)

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
