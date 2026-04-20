class Reminder < ApplicationRecord
  CHANNELS = %w[in_app email both].freeze
  RECURRENCES = %w[none daily weekly monthly].freeze

  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :user

  validates :remind_at, presence: true
  validates :message, presence: true
  validates :channel, inclusion: { in: CHANNELS }
  validates :recurrence, inclusion: { in: RECURRENCES }

  scope :pending, -> { where(fired_at: nil) }
  scope :due, -> { pending.where("remind_at <= ?", Time.current) }

  def fired?
    fired_at.present?
  end

  def fire!
    return if fired?
    Reminders::Fire.new(self).call
  end

  def next_occurrence_at
    case recurrence
    when "daily" then remind_at + 1.day
    when "weekly" then remind_at + 1.week
    when "monthly" then remind_at + 1.month
    end
  end
end
