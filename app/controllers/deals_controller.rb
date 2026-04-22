class DealsController < ApplicationController
  before_action :set_company, only: %i[new create]
  before_action :set_deal, only: %i[show edit update destroy advance]

  def index
    scope = Deal.kept.includes(:company, :owner).order(created_at: :desc)
    scope = scope.where(stage: params[:stage]) if params[:stage].present?
    @pagy, @deals = pagy(scope)
  end

  def pipeline
    @stages = Deal::STAGES
    @deals_by_stage = Deal.kept.includes(:company, :owner).group_by(&:stage)
  end

  def show
    @activities = @deal.activities.recent.limit(25)
  end

  def new
    @deal = @company.deals.new(owner: current_user)
  end

  def create
    @deal = @company.deals.new(deal_params)
    @deal.owner ||= current_user
    if @deal.save
      AuditLogger.record(user: current_user, action: "deal.created", subject: @deal)
      redirect_to @deal, notice: "Deal created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @company = @deal.company
  end

  def update
    if @deal.update(deal_params)
      redirect_to @deal, notice: "Deal updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @deal.destroy
      redirect_to deals_path, notice: "Deal deleted."
    else
      redirect_to @deal, alert: @deal.errors.full_messages.to_sentence.presence || "Deal could not be deleted."
    end
  end

  def advance
    stage = params[:stage]
    if Deal::STAGES.include?(stage)
      old = @deal.stage
      @deal.update_column(:stage, stage)
      Activity.create!(subject: @deal, user: current_user, kind: "stage_change",
                       occurred_at: Time.current, body: "Stage: #{old} → #{stage}")
      AuditLogger.record(user: current_user, action: "deal.stage_changed", subject: @deal,
                         metadata: { from: old, to: stage })
    end
    respond_to do |f|
      f.html { redirect_back fallback_location: deals_path }
      f.turbo_stream
    end
  end

  private

  def set_company
    @company = Company.kept.find_by!(slug: params[:company_id])
  end

  def set_deal
    @deal = Deal.kept.find(params[:id])
  end

  def deal_params
    params.require(:deal).permit(:name, :amount, :currency, :stage, :expected_close_on, :probability, :notes, :owner_id)
  end
end
