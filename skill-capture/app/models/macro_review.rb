# The macro-suitability layer. Every task is screened: could this be a deterministic macro instead of an
# AI call? A screen proposes; a person reviews. Only an approved review lets a macro run in place of the
# AI, and the saving is tallied as runs and tokens avoided.
class MacroReview < ApplicationRecord
  VERDICTS = %w[macro partial ai].freeze
  STATUSES = %w[proposed approved rejected needs_work].freeze
  # addin_js runs inside the add-in (Office.js) once approved; the other two are copied into Excel's
  # Automate tab or the VBA editor by the person doing the task.
  LANGUAGES = %w[addin_js office_script vba].freeze
  # An add-in script must define run(context): `async function run(…)`, or `const run = async (…) =>`.
  DEFINES_RUN = /(^|[^\w$])(async\s+)?function\s+run\s*\(|(^|[^\w$])(const|let|var)\s+run\s*=\s*(async\s*)?(\(|function)/

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
  def runnable_in_addin? = approved? && language == "addin_js" && code.match?(DEFINES_RUN)
  def approved? = status == "approved"
  def verdict_label = { "macro" => "Macro can do all of it", "partial" => "Macro can do part of it", "ai" => "Needs the AI" }[verdict]
  def reviewable_by?(u) = u.present? && (u.admin? || u.reviewer?)

  VISIBILITIES = %w[private firm market].freeze
  validates :visibility, inclusion: { in: VISIBILITIES }

  belongs_to :copied_from, class_name: "MacroReview", optional: true
  has_many :copies, class_name: "MacroReview", foreign_key: :copied_from_id, dependent: :nullify

  scope :shared, -> { approved.where(visibility: %w[firm market]) }

  def written_by_ai? = written_by == "ai"
  def confidence = suggestion["confidence"]
  def leaves_to_ai = Array(suggestion["leaves_to_ai"])
  def caveats = Array(suggestion["caveats"])
  def subject_label = subject_kind == "skill" ? "Skill #{subject_key}" : "Flow task"
  def skill = subject_kind == "skill" ? Skill.current(subject_key) : nil
  def visible_to?(u) = u.present? && (visibility != "private" || proposed_by_id == u.id || u.admin?)

  def notify_reviewers!
    User.active.where(role: %w[admin reviewer]).limit(25).find_each do |u|
      Notification.create!(user: u, subject: self, kind: "macro_review",
                           title: "#{written_by_ai? ? 'The AI wrote a macro' : 'A macro is waiting'}: #{title}",
                           body: "#{verdict_label}. Approve it and this task stops costing tokens.",
                           url: Rails.application.routes.url_helpers.macro_review_path(self))
    end
  end

  # Put an approved macro to work on another task or skill: the copy goes back through review, so
  # whoever takes it still checks that it fits.
  def copy_to!(kind:, key:, title:, user:)
    raise ArgumentError, "only an approved macro can be reused" unless approved?
    r = MacroReview.for_subject(kind, key) || MacroReview.new(subject_kind: kind, subject_key: key)
    raise ArgumentError, "#{key} already runs an approved macro" if r.approved?
    r.assign_attributes(title: title, verdict: verdict, score: score, signals: signals, app: app,
                        suggestion: suggestion.merge("copied_from" => subject_key),
                        reason: "Copied from “#{self.title}”. Check it fits this task before approving.",
                        status: "proposed", written_by: written_by, copied_from: self, proposed_by: user)
    r.save!
    AuditLog.record("macro_review.copied", user: user, subject: r, from: subject_key, to: key)
    r
  end

  # A macro as a file: enough to carry it to another flow, another install or another firm.
  def as_package
    { "format" => "skill-capture.macro/1", "title" => title, "app" => app, "language" => language, "code" => code,
      "verdict" => verdict, "score" => score, "signals" => signals, "reason" => reason,
      "steps" => Array(suggestion["steps"]), "leaves_to_ai" => leaves_to_ai, "caveats" => caveats,
      "written_by" => written_by, "from" => subject_key, "runs_saved" => runs_saved, "tokens_saved" => tokens_saved,
      "exported_at" => Time.current.utc.iso8601 }
  end

  def self.from_package(pkg, user:, kind: nil, key: nil, title: nil)
    pkg = pkg.to_h.stringify_keys
    raise ArgumentError, "that isn't a Skill Capture macro file" unless pkg["format"].to_s.start_with?("skill-capture.macro/")
    raise ArgumentError, "the file has no script in it" if pkg["code"].to_s.strip.length < 20
    kind ||= "skill"
    key ||= "imported:#{SecureRandom.hex(4)}"
    raise ArgumentError, "#{key} already runs an approved macro" if approved_for(kind, key)
    r = for_subject(kind, key) || new(subject_kind: kind, subject_key: key)
    r.assign_attributes(
      title: title.presence || pkg["title"].to_s.first(160).presence || "Imported macro",
      app: pkg["app"], verdict: pkg["verdict"].to_s.presence_in(VERDICTS) || "macro", score: pkg["score"].to_i,
      signals: pkg["signals"].is_a?(Hash) ? pkg["signals"] : {},
      suggestion: { "language" => pkg["language"].to_s.presence_in(LANGUAGES) || "addin_js", "code" => pkg["code"].to_s,
                    "steps" => Array(pkg["steps"]).map(&:to_s).first(12), "leaves_to_ai" => Array(pkg["leaves_to_ai"]).map(&:to_s),
                    "caveats" => Array(pkg["caveats"]).map(&:to_s), "imported_from" => pkg["from"] },
      reason: "Imported#{pkg['from'].present? ? " from “#{pkg['from']}”" : ''}. Read it before approving: it was written somewhere else.",
      written_by: pkg["written_by"].to_s.presence_in(%w[rules ai person]) || "person",
      status: "proposed", visibility: "private", proposed_by: user
    )
    r.save!
    AuditLog.record("macro_review.imported", user: user, subject: r, from: pkg["from"])
    r
  end

  def record_saving!(tokens)
    increment!(:runs_saved)
    increment!(:tokens_saved, tokens.to_i) if tokens.to_i.positive?
  end
end
