class FinishedGoodLot < ApplicationRecord
  belongs_to :product
  belongs_to :production_run
  has_many :movements, class_name: "FinishedGoodMovement", dependent: :destroy

  validates :lot_code, presence: true, uniqueness: true
  validates :produced_on, :quantity_produced, :quantity_on_hand, presence: true

  def trace
    {
      lot: self,
      run: production_run,
      consumptions: production_run.consumptions.includes(raw_material_lot: :raw_material)
    }
  end
end
