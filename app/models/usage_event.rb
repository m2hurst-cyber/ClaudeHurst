class UsageEvent < ApplicationRecord
  belongs_to :user, optional: true

  validates :session_key, :workflow_key, :http_method, :occurred_at, presence: true

  scope :recent, -> { order(occurred_at: :desc) }
  scope :expired, -> { where("occurred_at < ?", SkillCapture::Config.retention.ago) }
end
