class ProductionLine < ApplicationRecord
  has_many :production_runs, dependent: :restrict_with_error

  validates :name, :code, presence: true
  validates :code, uniqueness: true

  scope :active, -> { where(active: true) }
end
