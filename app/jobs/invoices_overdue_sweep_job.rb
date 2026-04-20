class InvoicesOverdueSweepJob < ApplicationJob
  queue_as :default

  def perform
    Invoice.where(status: %w[sent partial]).where("due_on < ?", Date.current).find_each do |inv|
      inv.mark_overdue! if inv.may_mark_overdue?
    end
  end
end
