class RawMaterial < ApplicationRecord
  include Discard::Model
  has_paper_trail

  CATEGORIES = %w[concentrate water can lid bottle cap label tray carton co2 sugar sweetener flavor other].freeze
  OWNERSHIPS = %w[copacker customer].freeze

  belongs_to :owned_by_company, class_name: "Company", optional: true
  has_many :lots, class_name: "RawMaterialLot", dependent: :destroy
  has_many :bom_items, dependent: :restrict_with_error

  validates :code, :name, :uom, presence: true
  validates :code, uniqueness: true
  validates :category, inclusion: { in: CATEGORIES }
  validates :owned_by, inclusion: { in: OWNERSHIPS }

  scope :active, -> { kept }

  def total_on_hand
    lots.sum(:quantity_on_hand)
  end

  def below_reorder?
    total_on_hand < reorder_point
  end
end
