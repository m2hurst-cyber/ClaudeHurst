class User < ApplicationRecord
  include Discard::Model

  devise :database_authenticatable, :recoverable, :rememberable, :validatable, :trackable

  ROLES = %w[admin sales ops finance].freeze

  has_one :microsoft_connection, dependent: :destroy
  has_many :communication_push_events, dependent: :nullify
  has_many :owned_companies, class_name: "Company", foreign_key: :owner_id, dependent: :nullify
  has_many :owned_deals, class_name: "Deal", foreign_key: :owner_id, dependent: :nullify
  has_many :activities, dependent: :destroy
  has_many :assigned_tasks, class_name: "Task", foreign_key: :assignee_id, dependent: :nullify
  has_many :reminders, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :audit_logs, dependent: :nullify

  validates :role, inclusion: { in: ROLES }
  validates :first_name, presence: true

  scope :active, -> { kept.where(active: true) }

  ROLES.each do |r|
    define_method(:"#{r}?") { role == r }
  end

  def display_name
    [first_name, last_name].compact.join(" ").presence || email
  end
end
