class ProductionRunConsumption < ApplicationRecord
  belongs_to :production_run
  belongs_to :raw_material_lot

  validates :quantity_planned, :uom, presence: true

  delegate :raw_material, to: :raw_material_lot
end
