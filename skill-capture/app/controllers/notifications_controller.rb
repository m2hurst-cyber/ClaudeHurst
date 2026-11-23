class NotificationsController < ApplicationController
  def index
    @pagy, @notifications = pagy(current_user.notifications.recent)
  end

  def read_all
    current_user.notifications.unread.update_all(read_at: Time.current)
    redirect_to notifications_path
  end
end
