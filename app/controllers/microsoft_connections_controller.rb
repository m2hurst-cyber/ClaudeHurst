class MicrosoftConnectionsController < ApplicationController
  def show
    @microsoft_connection = current_user.microsoft_connection
  end

  def create
    state = SecureRandom.hex(24)
    session[:microsoft_oauth_state] = state
    redirect_to MicrosoftGraph::Client.authorization_url(state: state), allow_other_host: true
  end

  def callback
    expected_state = session.delete(:microsoft_oauth_state).to_s
    unless expected_state.present? && ActiveSupport::SecurityUtils.secure_compare(params[:state].to_s, expected_state)
      redirect_to microsoft_connection_path, alert: "Microsoft connection could not be verified. Please try again."
      return
    end

    oauth_payload = MicrosoftGraph::Client.exchange_code(params.require(:code))
    profile = MicrosoftGraph::Client.new(connection: transient_connection(oauth_payload)).me
    connection = current_user.microsoft_connection || current_user.build_microsoft_connection

    connection.update!(
      tenant_id: profile["tenantId"].presence || ENV.fetch("MICROSOFT_TENANT_ID", "common"),
      microsoft_user_id: profile.fetch("id"),
      email: profile["mail"].presence || profile.fetch("userPrincipalName"),
      display_name: profile["displayName"],
      integration_payload: JSON.generate("access_value" => oauth_payload.fetch("access_token"), "refresh_value" => oauth_payload["refresh_token"]),
      integration_expires_at: Time.current + oauth_payload.fetch("expires_in", 3600).to_i.seconds,
      granted_scopes: oauth_payload["scope"].to_s
    )

    redirect_to microsoft_connection_path, notice: "Microsoft is connected."
  rescue KeyError, MicrosoftGraph::Client::Error => e
    redirect_to microsoft_connection_path, alert: e.message
  end

  def destroy
    current_user.microsoft_connection&.discard
    redirect_to microsoft_connection_path, notice: "Microsoft connection disconnected."
  end

  private

  def transient_connection(payload)
    MicrosoftConnection.new(integration_payload: JSON.generate("access_value" => payload.fetch("access_token")))
  end
end
