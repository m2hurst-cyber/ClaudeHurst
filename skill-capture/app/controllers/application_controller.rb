class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Pagy::Backend

  before_action :authenticate_user!
  helper_method :unread_notifications_count

  rescue_from Pundit::NotAuthorizedError do
    redirect_back fallback_location: root_path, alert: "You are not allowed to do that."
  end

  private

  def unread_notifications_count
    current_user ? current_user.notifications.unread.count : 0
  end
end
