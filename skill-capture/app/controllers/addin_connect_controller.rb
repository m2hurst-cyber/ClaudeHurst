# Opened by the task pane in an Office dialog. The person signs in here (normal
# session), confirms, and the page hands a personal add-in token back to the task
# pane with Office.context.ui.messageParent.
class AddinConnectController < ApplicationController
  include OfficeFraming

  layout "addin"

  def show
    @host = params[:host].to_s.first(40)
    @platform = params[:platform].to_s.first(40)
  end

  def create
    record, @token = AddinToken.issue!(user: current_user, host: params[:host], platform: params[:platform])
    AuditLog.record("addin.connected", user: current_user, subject: record, host: record.host, platform: record.platform)
    response.headers["Cache-Control"] = "no-store"
    render :connected
  end
end
