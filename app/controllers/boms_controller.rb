class BomsController < ApplicationController
  before_action :set_product, only: %i[index new create]
  before_action :set_bom, only: %i[show edit update destroy]

  def index
    @boms = @product.boms.order(version: :desc)
  end

  def show; end

  def new
    @bom = @product.boms.new(version: (@product.boms.maximum(:version) || 0) + 1, active: true)
    @bom.items.build
  end

  def create
    @bom = @product.boms.new(bom_params)
    if @bom.save
      redirect_to @bom, notice: "BOM created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @bom.items.build if @bom.items.empty?
  end

  def update
    if @bom.update(bom_params)
      redirect_to @bom, notice: "BOM updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    product = @bom.product
    @bom.destroy
    redirect_to product, notice: "BOM deleted."
  end

  private

  def set_product
    @product = Product.kept.find(params[:product_id])
  end

  def set_bom
    @bom = Bom.find(params[:id])
  end

  def bom_params
    params.require(:bom).permit(
      :version, :active, :yield_units, :notes,
      items_attributes: [:id, :raw_material_id, :quantity_per_unit, :uom, :position, :notes, :_destroy]
    )
  end
end
