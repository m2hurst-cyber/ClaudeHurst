class ReminderMailer < ApplicationMailer
  def fire
    @reminder = params[:reminder]
    mail(to: @reminder.user.email, subject: "[ClaudeHurst] Reminder")
  end
end
