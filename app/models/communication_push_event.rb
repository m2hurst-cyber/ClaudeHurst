class CommunicationPushEvent < ApplicationRecord
  CHANNELS = %w[email teams calendar].freeze
  STATUSES = %w[pending delivered failed skipped].freeze

  belongs_to :user, optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :event_type, :channel, :status, :deduplication_key, presence: true
  validates :channel, inclusion: { in: CHANNELS }
  validates :status, inclusion: { in: STATUSES }
  validates :deduplication_key, uniqueness: true

  scope :pending, -> { where(status: "pending") }
  scope :delivered, -> { where(status: "delivered") }
  scope :failed, -> { where(status: "failed") }

  def delivered!
    update!(status: "delivered", delivered_at: Time.current, error_message: nil)
  end

  def failed!(message)
    update!(status: "failed", error_message: message.to_s.truncate(1_000))
  end
end
