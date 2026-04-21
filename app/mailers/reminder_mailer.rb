class ReminderMailer < ApplicationMailer
  def fire
    @reminder = params[:reminder]
    mail(to: @reminder.target_user.email, subject: "[#{Branding.company_name}] Reminder")
  end
end
