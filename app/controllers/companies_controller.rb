class CompaniesController < ApplicationController
  before_action :set_company, only: %i[show edit update destroy]

  def index
    scope = Company.kept.by_name
    scope = scope.where("name ILIKE ?", "%#{params[:q]}%") if params[:q].present?
    @pagy, @companies = pagy(scope)
  end

  def show
    @contacts = @company.contacts.kept.by_name
    @deals = @company.deals.kept
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

  def set_company
    @company = Company.kept.find_by!(slug: params[:id]) || Company.kept.find(params[:id])
  end

  def company_params
    params.require(:company).permit(:name, :website, :industry, :status, :notes, :owner_id)
  end
end
