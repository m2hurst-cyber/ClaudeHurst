class User < ApplicationRecord
  ROLES = %w[admin reviewer member].freeze

  devise :database_authenticatable, :recoverable, :rememberable, :validatable

  has_many :notifications, dependent: :destroy
  has_many :addin_tokens, dependent: :destroy
  has_many :credit_entries, dependent: :restrict_with_error
  has_many :skill_grants, dependent: :delete_all
  has_many :sent_transfers, class_name: "SkillTransfer", foreign_key: :sender_id, dependent: :restrict_with_error
  has_many :received_transfers, class_name: "SkillTransfer", foreign_key: :recipient_id, dependent: :restrict_with_error

  def credits = credit_entries.sum(:amount)
  has_many :skill_votes, dependent: :destroy
  has_many :skill_prompts, dependent: :delete_all
  has_many :playbook_runs, dependent: :delete_all

  has_one :git_backup, dependent: :destroy
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

  # People in my department (or, when no department is set, people sharing one of my areas), me included.
  def department_colleagues
    scope = User.active
    if department.present?
      scope.where(department: department)
    elsif domains.any?
      scope.where("domains && ARRAY[?]::varchar[]", domains)
    else
      User.where(id: id)
    end.or(User.where(id: id))
  end
end
