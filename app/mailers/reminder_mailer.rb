class ReminderMailer < ApplicationMailer
  def fire
    @reminder = params[:reminder]
    mail(to: @reminder.user.email, subject: "[Great Southern Copacker] Reminder")
  end
end
