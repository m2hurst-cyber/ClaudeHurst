class RawMaterialLotsController < ApplicationController
  before_action :set_raw_material, only: %i[new create index]
  before_action :set_lot, only: %i[show edit update destroy]

  def index
    @lots = @raw_material.lots.order(received_on: :desc)
  end

  def show; end

  def new
    @lot = @raw_material.lots.new(received_on: Date.current)
  end

  def create
    @lot = @raw_material.lots.new(lot_params)
    @lot.quantity_on_hand = @lot.quantity_received if @lot.quantity_on_hand.blank?
    if @lot.save
      redirect_to @raw_material, notice: "Lot received."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @lot.update(lot_params)
      redirect_to @lot.raw_material, notice: "Lot updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    rm = @lot.raw_material
    @lot.destroy
    redirect_to rm, notice: "Lot removed."
  end

  private

  def set_raw_material
    @raw_material = RawMaterial.kept.find(params[:raw_material_id])
  end

  def set_lot
    @lot = RawMaterialLot.find(params[:id])
  end

  def lot_params
    params.require(:raw_material_lot).permit(:lot_code, :received_on, :expires_on,
                                              :quantity_received, :quantity_on_hand, :supplier, :notes)
  end
end
