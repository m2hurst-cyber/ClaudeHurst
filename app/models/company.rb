class Company < ApplicationRecord
  include Discard::Model
  has_paper_trail

  STATUSES = %w[prospect active churned].freeze

  belongs_to :owner, class_name: "User", optional: true

  has_many :contacts, dependent: :destroy
  has_many :deals, dependent: :destroy
  has_many :products, dependent: :destroy
  has_many :quotes, dependent: :destroy
  has_many :contracts, dependent: :destroy
  has_many :invoices, dependent: :destroy
  has_many :activities, as: :subject, dependent: :destroy

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  before_validation :set_slug, on: :create

  scope :by_name, -> { order(:name) }
  scope :prospects, -> { where(status: "prospect") }

  def to_param
    slug
  end

  def last_engagement_at
    activities.maximum(:occurred_at)
  end

  private

  def set_slug
    return if slug.present?
    base = name.to_s.parameterize
    candidate = base
    n = 2
    while Company.exists?(slug: candidate)
      candidate = "#{base}-#{n}"
      n += 1
    end
    self.slug = candidate
  end
end
