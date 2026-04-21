class ProductsController < ApplicationController
  before_action :set_company, only: %i[index new create]
  before_action :set_product, only: %i[show edit update destroy]

  def index
    @products = @company ? @company.products.kept : Product.kept.includes(:company)
  end

  def show
    @boms = @product.boms.order(version: :desc)
    @fg_lots = @product.finished_good_lots.order(produced_on: :desc).limit(20)
  end

  def new
    @product = @company.products.new(active: true, case_pack: 24)
  end

  def create
    @product = @company.products.new(product_params)
    if @product.save
      redirect_to @product, notice: "Product created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @company = @product.company
  end

  def update
    if @product.update(product_params)
      redirect_to @product, notice: "Product updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @product.discard
    redirect_to products_path, notice: "Product archived."
  end

  private

  def set_company
    @company = Company.kept.find_by!(slug: params[:company_id]) if params[:company_id]
  end

  def set_product
    @product = Product.kept.find(params[:id])
  end

  def product_params
    params.require(:product).permit(:sku, :name, :format, :case_pack, :gtin, :active, :description)
  end
end
