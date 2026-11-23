# People can see and revoke the Office installs connected to their account.
class ConnectedAppsController < ApplicationController
  def index
    @tokens = current_user.addin_tokens.live.order(last_used_at: :desc, created_at: :desc)
  end

  def destroy
    token = current_user.addin_tokens.live.find(params[:id])
    token.revoke!
    AuditLog.record("addin.revoked", user: current_user, subject: token)
    redirect_to connected_apps_path, notice: "Disconnected."
  end
end
