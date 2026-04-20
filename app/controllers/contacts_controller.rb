class ContactsController < ApplicationController
  before_action :set_company, only: %i[index new create]
  before_action :set_contact, only: %i[show edit update destroy]

  def index
    @contacts = @company.contacts.kept.by_name
  end

  def show; end

  def new
    @contact = @company.contacts.new
  end

  def create
    @contact = @company.contacts.new(contact_params)
    if @contact.save
      redirect_to @company, notice: "Contact added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @contact.update(contact_params)
      redirect_to @contact.company, notice: "Contact updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @contact.discard
    redirect_to @contact.company, notice: "Contact archived."
  end

  private

  def set_company
    @company = Company.kept.find(params[:company_id])
  end

  def set_contact
    @contact = Contact.kept.find(params[:id])
  end

  def contact_params
    params.require(:contact).permit(:first_name, :last_name, :title, :email, :phone, :primary)
  end
end
