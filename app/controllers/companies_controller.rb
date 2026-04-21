class CompaniesController < ApplicationController
  before_action :set_company, only: %i[show edit update destroy]

  def index
    scope = Company.kept.by_name
    scope = scope.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?
    @pagy, @companies = pagy(scope)
  end

  def show
    @primary_contacts = @company.contacts.kept.where(primary: true).by_name
    @secondary_contacts = @company.contacts.kept.where(primary: false).by_name
    @current_deals = @company.deals.kept.open.includes(:owner)
                             .order(Arel.sql("expected_close_on IS NULL, expected_close_on ASC")).limit(6)
    @current_tasks = current_tasks_scope.includes(:assignee).by_due.limit(6)
    @upcoming_runs = ProductionRun.upcoming.joins(:product)
                                  .where(products: { company_id: @company.id })
                                  .includes(:product, :production_line).limit(6)
    @tagged_reminders = Reminder.where(subject: @company).includes(:user).order(:remind_at).limit(6)
    @activities = @company.activities.recent.limit(25)
    @products = @company.products.kept
  end

  def new
    @company = Company.new
  end

  def create
    @company = Company.new(company_params)
    @company.owner ||= current_user
    if @company.save
      AuditLogger.record(user: current_user, action: "company.created", subject: @company)
      redirect_to @company, notice: "Company created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @company.update(company_params)
      redirect_to @company, notice: "Company updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @company.discard
    redirect_to companies_path, notice: "Company archived."
  end

  private

  def current_tasks_scope
    company_tasks = Task.open.where(subject: @company)
    deal_tasks = Task.open.where(subject_type: "Deal", subject_id: @company.deals.kept.select(:id))
    product_tasks = Task.open.where(subject_type: "Product", subject_id: @company.products.kept.select(:id))

    company_tasks.or(deal_tasks).or(product_tasks)
  end

  def set_company
    @company = Company.kept.find_by!(slug: params[:id]) || Company.kept.find(params[:id])
  end

  def company_params
    params.require(:company).permit(:name, :website, :industry, :status, :notes, :owner_id)
  end
end
