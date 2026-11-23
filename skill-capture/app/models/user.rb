class User < ApplicationRecord
  ROLES = %w[admin reviewer member].freeze

  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  has_many :notifications, dependent: :destroy
  has_many :addin_tokens, dependent: :destroy
  has_many :credit_entries, dependent: :restrict_with_error

  def credits = credit_entries.sum(:amount)

  validates :name, presence: true
  validates :role, inclusion: { in: ROLES }

  before_validation { self.domains = Array(domains).map { |d| d.to_s.strip.downcase }.reject(&:blank?).uniq }

  scope :active, -> { where(active: true) }

  ROLES.each { |r| define_method(:"#{r}?") { role == r } }

  # Reviewers own one or more domains (areas of work); admins review everything.
  def reviews?(domain)
    admin? || (reviewer? && domain.present? && domains.include?(domain))
  end

  def active_for_authentication? = super && active?

  # How this person appears as an actor in captured events.
  def actor_key = "user:#{id}"
end
