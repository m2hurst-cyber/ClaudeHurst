module Reminders
  class Fire
    def initialize(reminder)
      @reminder = reminder
    end

    def call
      return if @reminder.fired?
      ActiveRecord::Base.transaction do
        notify_in_app if channel_in?(%w[in_app both])
        notify_email if channel_in?(%w[email both])
        @reminder.update!(fired_at: Time.current)
        schedule_next_occurrence
      end
      AuditLogger.record(user: @reminder.user, action: "reminder.fired", subject: @reminder)
    end

    private

    def channel_in?(kinds)
      kinds.include?(@reminder.channel)
    end

    def notify_in_app
      Notification.create!(
        user: @reminder.target_user,
        subject: @reminder.subject,
        kind: "reminder",
        title: reminder_title,
        body: @reminder.message,
        url: subject_url
      )
    end

    def notify_email
      ReminderMailer.with(reminder: @reminder).fire.deliver_later
    end

    def subject_url
      return nil unless @reminder.subject
      Rails.application.routes.url_helpers.polymorphic_url(@reminder.subject, host: "localhost:3000") rescue nil
    end

    def schedule_next_occurrence
      return if @reminder.recurrence == "none"
      Reminder.create!(
        subject: @reminder.subject,
        user: @reminder.user,
        recipient: @reminder.recipient,
        remind_at: @reminder.next_occurrence_at,
        channel: @reminder.channel,
        recurrence: @reminder.recurrence,
        message: @reminder.message
      )
    end

    def reminder_title
      return "Reminder" if @reminder.target_user == @reminder.user

      "Reminder from #{@reminder.user.display_name}"
    end
  end
end
