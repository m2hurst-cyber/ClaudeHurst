class Invoice < ApplicationRecord
  include AASM
  has_paper_trail

  monetize :subtotal_cents, :tax_cents, :total_cents, :balance_cents

  belongs_to :company
  belongs_to :contract, optional: true
  belongs_to :production_run, optional: true
  has_many :line_items, class_name: "InvoiceLineItem", dependent: :destroy, inverse_of: :invoice
  has_many :payments, dependent: :destroy
  accepts_nested_attributes_for :line_items, allow_destroy: true, reject_if: :all_blank

  validates :number, presence: true, uniqueness: true

  before_validation :assign_number, on: :create
  before_save :recalculate_totals

  aasm column: :status, whiny_transitions: false do
    state :draft, initial: true
    state :sent, :paid, :partial, :void, :overdue

    event :send_out do
      transitions from: :draft, to: :sent, after: :stamp_issued
    end
    event :mark_paid do
      transitions from: [:sent, :partial, :overdue], to: :paid, after: :stamp_paid
    end
    event :mark_partial do
      transitions from: [:sent, :overdue], to: :partial
    end
    event :mark_overdue do
      transitions from: [:sent, :partial], to: :overdue
    end
    event :void_it do
      transitions from: [:draft, :sent, :partial, :overdue], to: :void
    end
  end

  def apply_payments!
    reload
    paid = payments.sum(:amount_cents)
    bal  = [total_cents - paid, 0].max
    update_columns(balance_cents: bal)
    if bal.zero? && total_cents.positive?
      mark_paid!
    elsif paid.positive? && bal.positive?
      mark_partial! if may_mark_partial?
    end
  end

  private

  def assign_number
    self.number ||= "INV-#{Date.current.year}-#{NumberSequence.next_for('invoice').to_s.rjust(4, '0')}"
  end

  def stamp_issued
    self.issued_on ||= Date.current
    self.due_on ||= Date.current + 30.days
    save(validate: false) if persisted?
  end

  def stamp_paid
    update_column(:paid_on, Date.current)
  end

  def recalculate_totals
    sub = line_items.reject(&:marked_for_destruction?).sum { |li| (li.quantity || 0) * (li.unit_price_cents || 0) }
    tax = line_items.reject(&:marked_for_destruction?).sum { |li| ((li.quantity || 0) * (li.unit_price_cents || 0) * (li.tax_rate || 0)).round }
    self.subtotal_cents = sub
    self.tax_cents = tax
    self.total_cents = sub + tax
    self.balance_cents = total_cents - payments.sum(:amount_cents)
  end
end
