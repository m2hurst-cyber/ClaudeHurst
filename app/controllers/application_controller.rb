class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Pagy::Backend

  before_action :authenticate_user!
  before_action :touch_last_seen

  helper_method :current_notifications_count

  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  def current_notifications_count
    return 0 unless current_user
    current_user.notifications.unread.count
  end

  def after_sign_out_path_for(_resource_or_scope)
    unauthenticated_root_path
  end

  private

  def touch_last_seen
    return unless current_user
    return if current_user.last_seen_at && current_user.last_seen_at > 5.minutes.ago
    current_user.update_column(:last_seen_at, Time.current)
  end

  def user_not_authorized
    flash[:alert] = "You are not authorized to perform this action."
    redirect_back fallback_location: root_path
  end
end
