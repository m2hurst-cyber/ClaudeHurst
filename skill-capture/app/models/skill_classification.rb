# What a skill is (any number of fields in the taxonomy) and which apps it uses.
# `field` is kept as the primary (first) field for places that need just one.
class SkillClassification < ApplicationRecord
  SOURCES = %w[ai rules user].freeze
  APPS = %w[Excel Word PowerPoint Outlook Teams Power\ BI SharePoint].freeze

  belongs_to :field, optional: true
  belongs_to :updated_by, class_name: "User", optional: true
  has_many :field_assignments, -> { order(:position) }, class_name: "SkillFieldAssignment", dependent: :delete_all
  has_many :fields, through: :field_assignments

  validates :skill_name, presence: true, uniqueness: true
  validates :source, inclusion: { in: SOURCES }
  validate { errors.add(:apps, "include unknown apps") unless (apps - APPS).empty? }

  before_validation { self.apps = Array(apps).map(&:to_s).select { |a| APPS.include?(a) }.uniq.sort_by { |a| APPS.index(a) } }

  def self.for(name) = find_by(skill_name: name)

  # Replace the field list (order = priority). Fields that are ancestors of another chosen
  # field are kept only if listed explicitly; duplicates are dropped.
  def set_fields!(list, source:)
    list = Array(list).compact.uniq
    transaction do
      field_assignments.delete_all
      list.each_with_index { |f, i| field_assignments.create!(field: f, position: i, source: source) }
      update_columns(field_id: list.first&.id)
    end
    field_assignments.reset
    self
  end

  def ordered_fields = field_assignments.includes(:field).map(&:field)
  def field_paths = ordered_fields.map(&:path)

  # Top-level fields this skill sits in (Finance, Legal, ...): more than one makes it a bridge.
  def roots = ordered_fields.map { |f| f.path.split("/").first }.uniq
  def bridge? = roots.size > 1 || apps.size > 1

  # "Excel → PowerPoint", "Finance → Legal": what this skill carries work across, in step order
  # for apps (e.g. collect charts in Excel, then build the appendix in PowerPoint).
  def bridge_label(skill = nil)
    return nil unless bridge?
    ordered = skill ? Capture::Classifier.observed_apps(skill) : []
    apps_seq = (ordered + apps).uniq
    parts = []
    parts << apps_seq.join(" → ") if apps_seq.size > 1
    # A cross-app skill is described by its apps; otherwise by the fields it spans.
    parts << roots.map { |r| Field.find_by(path: r)&.name || r.titleize }.join(" → ") if parts.empty? && roots.size > 1
    parts.join(" · ")
  end
end
