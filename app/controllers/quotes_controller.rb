class QuotesController < ApplicationController
  before_action :set_quote, only: %i[show edit update destroy send_out mark_accepted mark_rejected pdf]

  def index
    scope = Quote.includes(:company).order(created_at: :desc)
    scope = scope.where(status: params[:status]) if params[:status].present?
    @pagy, @quotes = pagy(scope)
  end

  def show; end

  def new
    @quote = Quote.new(company_id: params[:company_id], deal_id: params[:deal_id])
    @quote.line_items.build
  end

  def create
    @quote = Quote.new(quote_params)
    if @quote.save
      AuditLogger.record(user: current_user, action: "quote.created", subject: @quote)
      redirect_to @quote, notice: "Quote created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @quote.line_items.build if @quote.line_items.empty?
  end

  def update
    if @quote.update(quote_params)
      redirect_to @quote, notice: "Quote updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @quote.destroy
    redirect_to quotes_path, notice: "Quote deleted."
  end

  def send_out
    if @quote.send_out!
      Activity.create!(subject: @quote.company, user: current_user, kind: "document_sent",
                       occurred_at: Time.current, body: "Sent quote #{@quote.number}")
      DocumentMailer.with(document: @quote, user: current_user).send_document.deliver_later
      AuditLogger.record(user: current_user, action: "quote.sent", subject: @quote)
    end
    redirect_to @quote, notice: "Quote sent."
  end

  def mark_accepted
    @quote.mark_accepted!
    redirect_to @quote, notice: "Quote accepted."
  end

  def mark_rejected
    @quote.mark_rejected!
    redirect_to @quote, notice: "Quote rejected."
  end

  def pdf
    send_data Pdf::DocumentPdf.new(@quote).render,
              filename: "#{@quote.number}.pdf", type: "application/pdf", disposition: "inline"
  end

  private

  def set_quote
    @quote = Quote.find(params[:id])
  end

  def quote_params
    params.require(:quote).permit(
      :company_id, :deal_id, :contact_id, :issued_on, :expires_on, :notes, :terms, :currency,
      line_items_attributes: [:id, :product_id, :description, :quantity, :unit_price_cents, :tax_rate, :position, :_destroy]
    )
  end
end
