class FinishedGoodLotsController < ApplicationController
  before_action :set_lot, only: %i[show trace]

  def index
    scope = FinishedGoodLot.includes(:product).order(produced_on: :desc)
    @pagy, @lots = pagy(scope)
  end

  def show
    @movements = @lot.movements.order(occurred_at: :desc)
  end

  def trace
    @trace = @lot.trace
  end

  private

  def set_lot
    @lot = FinishedGoodLot.find(params[:id])
  end
end
