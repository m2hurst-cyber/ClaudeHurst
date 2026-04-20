class Quote < ApplicationRecord
  include AASM
  has_paper_trail

  monetize :subtotal_cents, :tax_cents, :total_cents

  belongs_to :company
  belongs_to :deal, optional: true
  belongs_to :contact, optional: true
  has_many :line_items, class_name: "QuoteLineItem", dependent: :destroy, inverse_of: :quote
  accepts_nested_attributes_for :line_items, allow_destroy: true, reject_if: :all_blank

  validates :number, presence: true, uniqueness: true

  before_validation :assign_number, on: :create
  before_save :recalculate_totals

  aasm column: :status, whiny_transitions: false do
    state :draft, initial: true
    state :sent, :accepted, :rejected, :expired

    event :send_out do
      transitions from: :draft, to: :sent, after: :stamp_issued
    end
    event :mark_accepted do
      transitions from: :sent, to: :accepted
    end
    event :mark_rejected do
      transitions from: :sent, to: :rejected
    end
    event :expire do
      transitions from: [:draft, :sent], to: :expired
    end
  end

  private

  def assign_number
    self.number ||= "Q-#{Date.current.year}-#{NumberSequence.next_for('quote').to_s.rjust(4, '0')}"
  end

  def stamp_issued
    update_columns(issued_on: Date.current, expires_on: (expires_on || 30.days.from_now.to_date))
  end

  def recalculate_totals
    sub = line_items.reject(&:marked_for_destruction?).sum { |li| (li.quantity || 0) * (li.unit_price_cents || 0) }
    tax = line_items.reject(&:marked_for_destruction?).sum { |li| ((li.quantity || 0) * (li.unit_price_cents || 0) * (li.tax_rate || 0)).round }
    self.subtotal_cents = sub
    self.tax_cents = tax
    self.total_cents = sub + tax
  end
end
