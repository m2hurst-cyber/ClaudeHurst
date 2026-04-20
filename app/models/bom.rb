class Bom < ApplicationRecord
  has_paper_trail

  belongs_to :product
  has_many :items, class_name: "BomItem", dependent: :destroy, inverse_of: :bom
  accepts_nested_attributes_for :items, allow_destroy: true, reject_if: :all_blank

  validates :version, presence: true, uniqueness: { scope: :product_id }

  scope :active, -> { where(active: true) }

  def code
    "#{product.sku}-BOM-v#{version}"
  end
end
