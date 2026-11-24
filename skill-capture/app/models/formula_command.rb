# One small command in a data provider's Excel formula library (Bloomberg BQL, FactSet). Worksheet
# skills reference commands by key; the add-in fills in the parameters when it builds a sheet.
# Starter commands install as unverified until someone with access to the provider checks them.
class FormulaCommand < ApplicationRecord
  PROVIDERS = { "bql" => "Bloomberg BQL", "factset" => "FactSet" }.freeze
  STATUSES = %w[unverified verified deprecated].freeze
  KEY = /\A[a-z0-9_]+\z/

  belongs_to :verified_by, class_name: "User", optional: true
  belongs_to :created_by, class_name: "User", optional: true

  validates :provider, presence: true, format: { with: /\A[a-z0-9-]+\z/ }
  validates :key, presence: true, format: { with: KEY, message: "must be lowercase letters, digits and underscores" }, uniqueness: { scope: :provider }
  validates :name, :syntax, presence: true
  validates :syntax, format: { with: /\A=/, message: "must be an Excel formula starting with =" }
  validates :status, inclusion: { in: STATUSES }
  validate { errors.add(:syntax, "has unbalanced quotes") if syntax.to_s.count('"').odd? }

  scope :live, -> { where.not(status: "deprecated") }

  def self.provider_name(p) = PROVIDERS[p] || p.to_s.titleize
  def params = syntax.to_s.scan(/\{([a-z_]+)\}/).flatten.uniq

  # A sample formula with defaults filled in (and the security left as a cell reference).
  def sample(security: "$B$3")
    syntax.gsub(/\{([a-z_]+)\}/) { |m| $1 == "security" ? security : (defaults[$1].presence || m) }
  end

  # What the add-in's builder needs.
  def to_builder = { syntax: syntax, defaults: defaults, status: status, name: name, description: description }

  # Skills (current versions) whose worksheet uses this command.
  def used_by
    Skill.published.where("skills.source -> 'worksheet' IS NOT NULL").where(domain: provider).select { |s| Capture::Worksheets.command_keys(s.source["worksheet"]).include?(key) }
  end
end
