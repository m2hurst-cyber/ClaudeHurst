require "test_helper"

class InvoiceTest < ActiveSupport::TestCase
  def company
    @company ||= Company.create!(name: "InvCo #{SecureRandom.hex(2)}", status: "active")
  end

  test "auto-assigns INV number" do
    inv = Invoice.create!(company: company)
    assert_match(/\AINV-\d{4}-\d{4}\z/, inv.number)
  end

  test "totals recalculate from line items" do
    inv = Invoice.new(company: company)
    inv.line_items.build(description: "Case", quantity: 10, unit_price_cents: 2_500, tax_rate: 0.1)
    inv.save!
    assert_equal 25_000, inv.subtotal_cents
    assert_equal 2_500, inv.tax_cents
    assert_equal 27_500, inv.total_cents
    assert_equal 27_500, inv.balance_cents
  end

  test "send_out moves draft to sent and stamps dates" do
    inv = Invoice.create!(company: company)
    inv.line_items.create!(description: "x", quantity: 1, unit_price_cents: 1_00, tax_rate: 0)
    inv.send_out!
    inv.reload
    assert inv.sent?
    assert_not_nil inv.issued_on
    assert_not_nil inv.due_on
  end

  test "apply_payments! marks paid when full balance covered" do
    inv = Invoice.create!(company: company)
    inv.line_items.create!(description: "x", quantity: 1, unit_price_cents: 10_000, tax_rate: 0)
    inv.send_out!
    inv.payments.create!(amount_cents: 10_000, received_on: Date.current, method: "ach")
    inv.apply_payments!
    assert inv.reload.paid?
    assert_equal 0, inv.balance_cents
  end
end
