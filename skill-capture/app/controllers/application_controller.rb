class ApplicationController < ActionController::Base
  include Pundit::Authorization
  include Pagy::Backend

  before_action :authenticate_user!
  helper_method :unread_notifications_count

  rescue_from Pundit::NotAuthorizedError do
    redirect_back fallback_location: root_path, alert: "You are not allowed to do that."
  end

  private

  # A .md response for LLMs and agents (?download=1 saves it as a file).
  def render_markdown(text, name)
    send_data text.to_s, type: "text/markdown; charset=utf-8", filename: "#{name.to_s.parameterize.presence || 'document'}.md",
                         disposition: params[:download].present? ? "attachment" : "inline"
  end

  def unread_notifications_count
    current_user ? current_user.notifications.unread.count : 0
  end
end
