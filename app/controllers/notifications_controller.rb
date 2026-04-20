class NotificationsController < ApplicationController
  def index
    @pagy, @notifications = pagy(current_user.notifications.recent)
  end

  def update
    notif = current_user.notifications.find(params[:id])
    notif.mark_read!
    redirect_back fallback_location: notifications_path
  end

  def destroy
    current_user.notifications.find(params[:id]).destroy
    redirect_back fallback_location: notifications_path
  end

  def mark_all_read
    current_user.notifications.unread.update_all(read_at: Time.current)
    redirect_back fallback_location: notifications_path
  end
end
