class SkillCandidate < ApplicationRecord
  STATUSES = %w[detected drafted approved rejected dismissed].freeze
  OPEN_STATUSES = %w[detected drafted].freeze
  ORIGINS = %w[detected manual].freeze
  STEP_SEPARATOR = ">".freeze

  belongs_to :skill, optional: true
  belongs_to :reviewer, class_name: "User", optional: true
  belongs_to :requested_by, class_name: "User", optional: true

  validates :signature, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :origin, inclusion: { in: ORIGINS }
  validates :draft_name, format: { with: Skill::NAME_FORMAT, message: "must be lowercase letters, digits and hyphens" },
                         length: { maximum: 64 }, allow_blank: true

  scope :open, -> { where(status: OPEN_STATUSES) }
  scope :recent, -> { order(last_seen_at: :desc, created_at: :desc) }
  # Candidates whose step sequence strictly contains the given steps.
  scope :covering, ->(steps) {
    sig = signature_for(steps)
    where("(? || signature || ?) LIKE ?", STEP_SEPARATOR, STEP_SEPARATOR,
          "%#{STEP_SEPARATOR}#{sanitize_sql_like(sig)}#{STEP_SEPARATOR}%")
      .where.not(signature: sig)
  }

  def self.signature_for(steps) = Array(steps).join(STEP_SEPARATOR)

  def open? = OPEN_STATUSES.include?(status)
  def drafted? = draft_body.present?

  def step_descriptions
    steps.map { |s| SkillCapture::Catalog.describe(s) }
  end

  def display_title
    draft_title.presence || steps.map { |s| s.split("#").reverse.join(" ").humanize }.join(" → ").truncate(90)
  end

  def contributors
    User.where(id: contributor_ids)
  end

  # Governance: the process owners for the workflow's domain (plus admins) review it.
  def reviewer_roles
    %w[sales ops finance].include?(domain) ? ["admin", domain] : ["admin"]
  end

  def reviewers
    User.active.where(role: reviewer_roles)
  end

  def reviewable_by?(user)
    user.present? && reviewer_roles.include?(user.role)
  end

  def notify_reviewers!(title)
    reviewers.find_each do |u|
      Notification.create!(user: u, subject: self, kind: "skill_candidate", title: title,
                           body: "Seen #{occurrence_count}× by #{distinct_user_count} people. Review and publish it as a skill.",
                           url: Rails.application.routes.url_helpers.skill_candidate_path(self))
    end
  end
end
