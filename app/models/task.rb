class Task < ApplicationRecord
  include Discard::Model

  PRIORITIES = %w[low normal high urgent].freeze

  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :assignee, class_name: "User", optional: true

  validates :title, presence: true
  validates :priority, inclusion: { in: PRIORITIES }

  scope :open, -> { kept.where(completed_at: nil) }
  scope :overdue, -> { open.where("due_on < ?", Date.current) }
  scope :by_due, -> { order(Arel.sql("due_on IS NULL, due_on ASC")) }

  def complete!
    update!(completed_at: Time.current)
  end

  def completed?
    completed_at.present?
  end
end
