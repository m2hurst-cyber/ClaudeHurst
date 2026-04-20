class ProductionRunsController < ApplicationController
  before_action :set_run, only: %i[show edit update destroy release start_run complete close cancel create_invoice]

  def index
    scope = ProductionRun.includes(:product, :production_line).order(scheduled_start: :desc)
    scope = scope.where(status: params[:status]) if params[:status].present?
    @pagy, @runs = pagy(scope)
  end

  def show
    @consumptions = @run.consumptions.includes(raw_material_lot: :raw_material)
    @fg_lots = @run.finished_good_lots
  end

  def new
    @run = ProductionRun.new(scheduled_start: 1.day.from_now, owner: current_user)
  end

  def create
    @run = ProductionRun.new(run_params)
    @run.owner ||= current_user
    if @run.save
      redirect_to @run, notice: "Run scheduled."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @run.update(run_params)
      redirect_to @run, notice: "Run updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @run.destroy
    redirect_to production_runs_path, notice: "Run deleted."
  end

  def release
    Production::ReleaseRun.new(@run).call
    redirect_to @run, notice: "Run released — raw materials reserved."
  rescue => e
    redirect_to @run, alert: "Release failed: #{e.message}"
  end

  def start_run
    @run.start_run!
    redirect_to @run, notice: "Run started."
  end

  def complete
    actual = params[:actual_units].to_i
    Production::CompleteRun.new(@run, actual_units: actual).call
    redirect_to @run, notice: "Run completed."
  rescue => e
    redirect_to @run, alert: "Complete failed: #{e.message}"
  end

  def close
    @run.close!
    redirect_to @run, notice: "Run closed."
  end

  def cancel
    @run.cancel!
    redirect_to @run, notice: "Run cancelled."
  end

  def create_invoice
    redirect_to new_invoice_path(production_run_id: @run.id)
  end

  private

  def set_run
    @run = ProductionRun.find(params[:id])
  end

  def run_params
    params.require(:production_run).permit(:product_id, :production_line_id, :scheduled_start, :scheduled_end,
                                            :planned_units, :owner_id, :notes)
  end
end
