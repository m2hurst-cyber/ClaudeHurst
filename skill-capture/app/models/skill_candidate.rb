class SkillCandidate < ApplicationRecord
  STATUSES = %w[detected drafted approved rejected dismissed].freeze
  OPEN_STATUSES = %w[detected drafted].freeze
  STEP_SEPARATOR = ">".freeze

  belongs_to :skill, optional: true
  belongs_to :reviewer, class_name: "User", optional: true
  belongs_to :requested_by, class_name: "User", optional: true

  validates :signature, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :origin, inclusion: { in: %w[detected manual] }
  validates :draft_name, format: { with: Skill::NAME_FORMAT, message: "must be lowercase letters, digits and hyphens" },
                         length: { maximum: 64 }, allow_blank: true

  scope :open, -> { where(status: OPEN_STATUSES) }
  scope :recent, -> { order(last_seen_at: :desc, created_at: :desc) }
  # Candidates whose step sequence strictly contains the given steps.
  scope :covering, ->(steps) {
    sig = signature_for(steps)
    where("(? || signature || ?) LIKE ?", STEP_SEPARATOR, STEP_SEPARATOR,
          "%#{STEP_SEPARATOR}#{sanitize_sql_like(sig)}#{STEP_SEPARATOR}%").where.not(signature: sig)
  }

  def self.signature_for(steps) = Array(steps).join(STEP_SEPARATOR)

  def open? = OPEN_STATUSES.include?(status)
  def drafted? = draft_body.present?

  def step_labels = ActionDefinition.labels_for(steps)

  def display_title
    draft_title.presence || steps.map { |s| ActionDefinition.label_for(s) }.join(" → ").truncate(90)
  end

  def contributor_names = contributors.map { |c| c["name"].presence || c["key"] }

  def reviewers
    User.active.select { |u| u.reviews?(domain) }
  end

  def reviewable_by?(user) = user.present? && user.reviews?(domain)

  def notify_reviewers!(title)
    reviewers.each do |u|
      Notification.create!(user: u, subject: self, kind: "skill_candidate", title: title,
                           body: "Seen #{occurrence_count}× by #{distinct_actor_count} people.",
                           url: Rails.application.routes.url_helpers.skill_candidate_path(self))
    end
  end
end
