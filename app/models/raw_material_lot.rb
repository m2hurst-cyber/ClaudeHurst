class RawMaterialLot < ApplicationRecord
  belongs_to :raw_material
  has_many :production_run_consumptions, dependent: :restrict_with_error

  validates :lot_code, :received_on, :quantity_received, :quantity_on_hand, presence: true
  validates :lot_code, uniqueness: { scope: :raw_material_id }

  scope :available, -> { where("quantity_on_hand > 0").order(received_on: :asc) }

  def consume!(qty)
    raise ArgumentError, "qty must be positive" if qty.to_d <= 0
    raise "insufficient lot quantity" if qty.to_d > quantity_on_hand
    update!(quantity_on_hand: quantity_on_hand - qty.to_d)
  end
end
