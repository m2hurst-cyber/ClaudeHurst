class AuditLog < ApplicationRecord
  belongs_to :user, optional: true
  belongs_to :source, optional: true
  belongs_to :subject, polymorphic: true, optional: true

  validates :action, presence: true
  scope :recent, -> { order(created_at: :desc) }

  def self.record(action, user: nil, source: nil, subject: nil, **metadata)
    create!(action: action, user: user, source: source, subject: subject, metadata: metadata)
  rescue => e
    Rails.logger.error("AuditLog failed: #{e.class}: #{e.message}")
    nil
  end
end
