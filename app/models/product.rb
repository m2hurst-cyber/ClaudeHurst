class Product < ApplicationRecord
  include Discard::Model
  has_paper_trail

  belongs_to :company
  has_many :boms, dependent: :destroy
  has_many :production_runs, dependent: :restrict_with_error
  has_many :finished_good_lots, dependent: :destroy

  validates :sku, :name, presence: true
  validates :sku, uniqueness: { scope: :company_id }

  scope :active, -> { kept.where(active: true) }

  def active_bom
    boms.where(active: true).order(version: :desc).first
  end

  def display_name
    "#{name} (#{sku})"
  end
end
