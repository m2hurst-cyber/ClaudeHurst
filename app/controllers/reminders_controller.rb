class RemindersController < ApplicationController
  before_action :set_reminder, only: %i[show edit update destroy fire]

  def index
    scope = Reminder.where(user: current_user).order(remind_at: :asc)
    @pagy, @reminders = pagy(scope)
  end

  def show; end

  def new
    @reminder = Reminder.new(user: current_user, remind_at: 1.hour.from_now, channel: "both", recurrence: "none")
  end

  def create
    @reminder = Reminder.new(reminder_params.merge(user: current_user))
    if @reminder.save
      redirect_to reminders_path, notice: "Reminder scheduled."
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

  def reminder_params
    params.require(:reminder).permit(:remind_at, :channel, :recurrence, :message)
  end
end
