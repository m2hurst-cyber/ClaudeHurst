# The macro-suitability layer. Every task is screened: could this be a deterministic macro instead of an
# AI call? A screen proposes; a person reviews. Only an approved review lets a macro run in place of the
# AI, and the saving is tallied as runs and tokens avoided.
class MacroReview < ApplicationRecord
  VERDICTS = %w[macro partial ai].freeze
  STATUSES = %w[proposed approved rejected needs_work].freeze
  # addin_js runs inside the add-in (Office.js) once approved; the other two are copied into Excel's
  # Automate tab or the VBA editor by the person doing the task.
  LANGUAGES = %w[addin_js office_script vba].freeze

  belongs_to :proposed_by, class_name: "User", optional: true
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :subject_kind, inclusion: { in: %w[skill flow_step] }
  validates :subject_key, :title, presence: true
  validates :verdict, inclusion: { in: VERDICTS }
  validates :status, inclusion: { in: STATUSES }
  validate { errors.add(:suggestion, "needs code before it can be approved") if status == "approved" && code.blank? }

  scope :open, -> { where(status: %w[proposed needs_work]) }
  scope :approved, -> { where(status: "approved") }

  def self.for_subject(kind, key) = find_by(subject_kind: kind, subject_key: key)
  def self.approved_for(kind, key) = approved.find_by(subject_kind: kind, subject_key: key)

  def code = suggestion["code"].to_s
  def language = suggestion["language"].presence || "addin_js"
  def language_label = { "addin_js" => "Add-in script (Office.js)", "office_script" => "Office Script (TypeScript)", "vba" => "VBA" }[language]
  def runnable_in_addin? = approved? && language == "addin_js" && code.present?
  def approved? = status == "approved"
  def verdict_label = { "macro" => "Macro can do all of it", "partial" => "Macro can do part of it", "ai" => "Needs the AI" }[verdict]
  def reviewable_by?(u) = u.present? && (u.admin? || u.reviewer?)

  def record_saving!(tokens)
    increment!(:runs_saved)
    increment!(:tokens_saved, tokens.to_i) if tokens.to_i.positive?
  end
end
