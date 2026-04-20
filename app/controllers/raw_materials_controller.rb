class RawMaterialsController < ApplicationController
  before_action :set_raw_material, only: %i[show edit update destroy]

  def index
    scope = RawMaterial.kept.order(:name)
    scope = scope.where(category: params[:category]) if params[:category].present?
    @pagy, @raw_materials = pagy(scope)
  end

  def show
    @lots = @raw_material.lots.order(received_on: :desc)
  end

  def new
    @raw_material = RawMaterial.new(uom: "each", category: "other", owned_by: "copacker")
  end

  def create
    @raw_material = RawMaterial.new(rm_params)
    if @raw_material.save
      redirect_to @raw_material, notice: "Raw material created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @raw_material.update(rm_params)
      redirect_to @raw_material, notice: "Raw material updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @raw_material.discard
    redirect_to raw_materials_path, notice: "Raw material archived."
  end

  private

  def set_raw_material
    @raw_material = RawMaterial.kept.find(params[:id])
  end

  def rm_params
    params.require(:raw_material).permit(:code, :name, :category, :uom, :reorder_point, :owned_by,
                                         :owned_by_company_id, :description)
  end
end
