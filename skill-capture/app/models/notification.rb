class Notification < ApplicationRecord
  belongs_to :user
  belongs_to :subject, polymorphic: true, optional: true

  validates :kind, :title, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc) }
end
