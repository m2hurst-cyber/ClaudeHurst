class ContractsController < ApplicationController
  before_action :set_contract, only: %i[show edit update destroy mark_signed activate pdf]

  def index
    scope = Contract.includes(:company).order(created_at: :desc)
    @pagy, @contracts = pagy(scope)
  end

  def show; end

  def new
    @contract = Contract.new(company_id: params[:company_id])
    @contract.pricing_tiers.build
  end

  def create
    @contract = Contract.new(contract_params)
    if @contract.save
      AuditLogger.record(user: current_user, action: "contract.created", subject: @contract)
      redirect_to @contract, notice: "Contract created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @contract.pricing_tiers.build if @contract.pricing_tiers.empty?
  end

  def update
    if @contract.update(contract_params)
      redirect_to @contract, notice: "Contract updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @contract.destroy
    redirect_to contracts_path, notice: "Contract deleted."
  end

  def mark_signed
    @contract.mark_signed!
    Activity.create!(subject: @contract.company, user: current_user, kind: "document_sent",
                     occurred_at: Time.current, body: "Contract #{@contract.number} signed")
    redirect_to @contract, notice: "Contract marked signed."
  end

  def activate
    @contract.activate!
    redirect_to @contract, notice: "Contract activated."
  end

  def pdf
    send_data Pdf::ContractPdf.new(@contract).render,
              filename: "#{@contract.number}.pdf", type: "application/pdf", disposition: "inline"
  end

  private

  def set_contract
    @contract = Contract.find(params[:id])
  end

  def contract_params
    params.require(:contract).permit(
      :company_id, :title, :start_on, :end_on, :payment_terms, :minimum_run_units, :terms,
      pricing_tiers_attributes: [:id, :product_id, :min_quantity, :unit_price_cents, :_destroy]
    )
  end
end
