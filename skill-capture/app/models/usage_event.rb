class UsageEvent < ApplicationRecord
  belongs_to :source

  validates :actor_key, :session_key, :action_key, :occurred_at, presence: true

  scope :expired, -> { where("occurred_at < ?", Capture::Config.retention.ago) }
end
