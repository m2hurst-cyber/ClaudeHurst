class DashboardsController < ApplicationController
  def show
    @open_deals_amount = Deal.open.sum(:amount_cents)
    @open_deals_count = Deal.open.count
    @overdue_invoices = Invoice.where(status: %w[sent partial overdue]).where("due_on < ?", Date.current).order(:due_on).limit(10)
    @upcoming_runs = ProductionRun.upcoming.limit(10)
    @my_tasks = Task.open.where(assignee: current_user).by_due.limit(10)
    @low_stock = RawMaterial.active.select { |rm| rm.below_reorder? }.first(10)
    @recent_notifications = current_user.notifications.recent.limit(8)
  end
end
