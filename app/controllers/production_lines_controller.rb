class ProductionLinesController < ApplicationController
  before_action :set_line, only: %i[show edit update destroy]

  def index
    @lines = ProductionLine.order(:name)
  end

  def show
    runs = @line.production_runs.order(:scheduled_start)
    @active_runs   = runs.where(status: %w[in_progress released])
    @upcoming_runs = runs.where(status: "planned").limit(20)
    @recent_runs   = runs.where(status: %w[completed closed]).reorder(scheduled_start: :desc).limit(10)
  end

  def new
    @line = ProductionLine.new(active: true)
  end

  def create
    @line = ProductionLine.new(line_params)
    if @line.save
      redirect_to @line, notice: "Line created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @line.update(line_params)
      redirect_to @line, notice: "Line updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @line.destroy
    redirect_to production_lines_path, notice: "Line removed."
  end

  private

  def set_line
    @line = ProductionLine.find(params[:id])
  end

  def line_params
    params.require(:production_line).permit(:name, :code, :hourly_capacity, :active, :description)
  end
end
