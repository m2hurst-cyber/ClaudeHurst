class PaymentsController < ApplicationController
  before_action :set_invoice, only: %i[new create]
  before_action :set_payment, only: %i[destroy]

  def new
    @payment = @invoice.payments.new(received_on: Date.current, method: "ach",
                                      amount_cents: @invoice.balance_cents)
  end

  def create
    @payment = @invoice.payments.new(payment_params)
    if @payment.save
      redirect_to @invoice, notice: "Payment recorded."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    inv = @payment.invoice
    @payment.destroy
    inv.apply_payments!
    redirect_to inv, notice: "Payment removed."
  end

  private

  def set_invoice
    @invoice = Invoice.find(params[:invoice_id])
  end

  def set_payment
    @payment = Payment.find(params[:id])
  end

  def payment_params
    params.require(:payment).permit(:amount_cents, :received_on, :method, :reference, :notes)
  end
end
