class FinishedGoodMovementsController < ApplicationController
  before_action :set_lot, only: %i[new create]

  def new
    @movement = @lot.movements.new(occurred_at: Time.current, kind: "ship")
  end

  def create
    @movement = @lot.movements.new(movement_params.merge(user: current_user))
    @movement.occurred_at ||= Time.current
    qty_delta = case @movement.kind
                when "ship", "scrap" then -@movement.quantity.to_i.abs
                when "produce" then @movement.quantity.to_i.abs
                else @movement.quantity.to_i
                end
    @movement.quantity = qty_delta
    ActiveRecord::Base.transaction do
      @movement.save!
      @lot.update!(quantity_on_hand: @lot.quantity_on_hand + qty_delta)
    end
    redirect_to @lot, notice: "Movement recorded."
  rescue => e
    redirect_to @lot, alert: "Failed: #{e.message}"
  end

  private

  def set_lot
    @lot = FinishedGoodLot.find(params[:finished_good_lot_id])
  end

  def movement_params
    params.require(:finished_good_movement).permit(:kind, :quantity, :occurred_at, :notes)
  end
end
