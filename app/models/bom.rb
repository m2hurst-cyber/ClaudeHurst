class Bom < ApplicationRecord
  has_paper_trail

  belongs_to :product
  has_many :items, class_name: "BomItem", dependent: :destroy, inverse_of: :bom
  accepts_nested_attributes_for :items, allow_destroy: true, reject_if: :all_blank

  validates :version, presence: true, uniqueness: { scope: :product_id }
  validates :yield_units, numericality: { greater_than: 0 }
  validate :only_one_active_bom_per_product

  before_validation :assign_next_version, on: :create
  after_save :deactivate_other_boms, if: :saved_change_to_active?

  scope :active, -> { where(active: true) }

  def self.next_version_for(product)
    product.boms.maximum(:version).to_i + 1
  end

  def code
    "#{product.sku}-BOM-v#{version}"
  end

  private

  def assign_next_version
    self.version ||= self.class.next_version_for(product)
  end

  def only_one_active_bom_per_product
    return unless active?
    return unless product_id

    existing = product.boms.active.where.not(id: id).exists?
    errors.add(:active, "BOM already exists for this product") if existing
  end

  def deactivate_other_boms
    return unless active?

    product.boms.where.not(id: id).update_all(active: false, updated_at: Time.current)
  end
end
