class SkillClassification < ApplicationRecord
  SOURCES = %w[ai rules user].freeze
  APPS = %w[Excel Word PowerPoint Outlook Teams Power\ BI SharePoint].freeze

  belongs_to :field, optional: true
  belongs_to :updated_by, class_name: "User", optional: true

  validates :skill_name, presence: true, uniqueness: true
  validates :source, inclusion: { in: SOURCES }
  validate { errors.add(:apps, "include unknown apps") unless (apps - APPS).empty? }

  before_validation { self.apps = Array(apps).map(&:to_s).select { |a| APPS.include?(a) }.uniq.sort_by { |a| APPS.index(a) } }

  def self.for(name) = find_by(skill_name: name)
  def by_person? = confirmed
end
