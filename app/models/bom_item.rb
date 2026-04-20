class BomItem < ApplicationRecord
  belongs_to :bom, inverse_of: :items
  belongs_to :raw_material

  validates :quantity_per_unit, :uom, presence: true
  validates :quantity_per_unit, numericality: { greater_than: 0 }
end
