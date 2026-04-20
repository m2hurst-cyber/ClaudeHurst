class InvoicesController < ApplicationController
  before_action :set_invoice, only: %i[show edit update destroy send_out void_it pdf]

  def index
    scope = Invoice.includes(:company).order(created_at: :desc)
    scope = scope.where(status: params[:status]) if params[:status].present?
    @pagy, @invoices = pagy(scope)
  end

  def show
    @payments = @invoice.payments.order(received_on: :desc)
  end

  def new
    @invoice = Invoice.new(company_id: params[:company_id], contract_id: params[:contract_id],
                           production_run_id: params[:production_run_id])
    prefill_from_run if params[:production_run_id].present?
    @invoice.line_items.build if @invoice.line_items.empty?
  end

  def create
    @invoice = Invoice.new(invoice_params)
    if @invoice.save
      AuditLogger.record(user: current_user, action: "invoice.created", subject: @invoice)
      redirect_to @invoice, notice: "Invoice created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @invoice.line_items.build if @invoice.line_items.empty?
  end

  def update
    if @invoice.update(invoice_params)
      redirect_to @invoice, notice: "Invoice updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @invoice.destroy
    redirect_to invoices_path, notice: "Invoice deleted."
  end

  def send_out
    if @invoice.send_out!
      Activity.create!(subject: @invoice.company, user: current_user, kind: "document_sent",
                       occurred_at: Time.current, body: "Sent invoice #{@invoice.number}")
      DocumentMailer.with(document: @invoice, user: current_user).send_document.deliver_later
      AuditLogger.record(user: current_user, action: "invoice.sent", subject: @invoice)
    end
    redirect_to @invoice, notice: "Invoice sent."
  end

  def void_it
    authorize @invoice, :void?
    @invoice.void_it!
    AuditLogger.record(user: current_user, action: "invoice.voided", subject: @invoice)
    redirect_to @invoice, notice: "Invoice voided."
  end

  def pdf
    send_data Pdf::DocumentPdf.new(@invoice).render,
              filename: "#{@invoice.number}.pdf", type: "application/pdf", disposition: "inline"
  end

  private

  def set_invoice
    @invoice = Invoice.find(params[:id])
  end

  def invoice_params
    params.require(:invoice).permit(
      :company_id, :contract_id, :production_run_id, :issued_on, :due_on, :notes, :currency,
      line_items_attributes: [:id, :product_id, :description, :quantity, :unit_price_cents, :tax_rate, :position, :_destroy]
    )
  end

  def prefill_from_run
    run = ProductionRun.find(params[:production_run_id])
    @invoice.company_id = run.product.company_id
    return unless run.actual_units
    contract = run.product.company.contracts.where(status: %w[signed active]).order(created_at: :desc).first
    unit_price = contract&.unit_price_cents_for(run.product, run.actual_units) || 0
    @invoice.contract = contract
    @invoice.line_items.build(
      product_id: run.product_id,
      description: "#{run.product.display_name} — run #{run.number}",
      quantity: run.actual_units,
      unit_price_cents: unit_price
    )
  end
end
