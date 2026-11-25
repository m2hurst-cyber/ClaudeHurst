# Everything connected to this person's account, in one place: the Office add-in signing
# them in, and the agents they have given a key to. Each with a switch they can flip back.
#
# Firm-wide collectors are an admin's business and appear only for admins, read-only here,
# so one page answers "what can reach my work" without pretending a member owns them.
class ConnectionsController < ApplicationController
  before_action :load_connection, only: %i[update destroy]

  def index
    @connections = current_user.addin_tokens.live.recent.to_a
    @sources = Source.order(:name) if current_user.admin?
    @issued = flash[:issued_token] # shown once, never stored
    @issued_for = flash[:issued_for]
  end

  def create
    name = params[:name].to_s.strip.presence || "Agent"
    _record, token = AddinToken.issue!(user: current_user, kind: "mcp", name: name)
    AuditLog.record("connection.created", user: current_user, name: name, kind: "mcp")
    redirect_to connections_path, flash: { issued_token: token, issued_for: name }
  end

  def update
    @connection.switch!(params[:enabled])
    AuditLog.record("connection.switched", user: current_user, subject: @connection,
                    name: @connection.label, on: @connection.enabled?)
    redirect_to connections_path, notice: "#{@connection.label} is #{@connection.enabled? ? 'on' : 'off'}."
  end

  def destroy
    @connection.revoke!
    AuditLog.record("connection.revoked", user: current_user, subject: @connection, name: @connection.label)
    redirect_to connections_path, notice: "#{@connection.label} can no longer reach your work."
  end

  private

  def load_connection
    @connection = current_user.addin_tokens.live.find_by(id: params[:id])
    redirect_to(connections_path, alert: "No such connection.") if @connection.nil?
  end
end
