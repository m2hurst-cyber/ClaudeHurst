class RemindersController < ApplicationController
  before_action :set_reminder, only: %i[show edit update destroy fire]
  before_action :set_subject, only: %i[new create]

  def index
    scope = Reminder.where(user: current_user).order(remind_at: :asc)
    @pagy, @reminders = pagy(scope)
  end

  def show; end

  def new
    @reminder = Reminder.new(user: current_user, subject: @subject, remind_at: 1.hour.from_now, channel: "both", recurrence: "none")
  end

  def create
    @reminder = Reminder.new(reminder_params.merge(user: current_user, subject: @subject))
    if @reminder.save
      redirect_to(@subject || reminders_path, notice: "Reminder scheduled.")
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @reminder.update(reminder_params)
      redirect_to reminders_path, notice: "Reminder updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @reminder.destroy
    redirect_to reminders_path, notice: "Reminder deleted."
  end

  def fire
    @reminder.fire!
    redirect_to reminders_path, notice: "Reminder fired."
  end

  private

  def set_reminder
    @reminder = Reminder.find(params[:id])
  end

  def set_subject
    @subject = if params[:company_id].present?
                 find_company(params[:company_id])
               elsif params[:deal_id].present?
                 Deal.kept.find(params[:deal_id])
               elsif params[:product_id].present?
                 Product.kept.find(params[:product_id])
               elsif params.dig(:reminder, :subject_type).present? && params.dig(:reminder, :subject_id).present?
                 find_subject(params[:reminder][:subject_type], params[:reminder][:subject_id])
               end
  end

  def find_company(reference)
    Company.kept.find_by(slug: reference) || Company.kept.find(reference)
  end

  def find_subject(subject_type, subject_id)
    case subject_type
    when "Company"
      Company.kept.find(subject_id)
    when "Deal"
      Deal.kept.find(subject_id)
    when "Product"
      Product.kept.find(subject_id)
    end
  end

  def reminder_params
    params.require(:reminder).permit(:remind_at, :channel, :recurrence, :message)
  end
end
