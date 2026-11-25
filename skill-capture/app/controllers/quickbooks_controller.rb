# The QuickBooks authorisation round trip, and the change notification Intuit sends.
class QuickbooksController < ApplicationController
  skip_before_action :verify_authenticity_token, only: :webhook, raise: false
  skip_before_action :authenticate_user!, only: :webhook
  before_action :admins_only, except: :webhook

  # Off to Intuit, with a signed state so the way back can be trusted.
  def connect
    unless Capture::Quickbooks::Config.configured?
      return redirect_to admin_integrations_path,
                         alert: "QuickBooks needs #{Capture::Quickbooks::Config.missing.to_sentence} set before it can be connected."
    end
    redirect_to Capture::Quickbooks::Oauth.authorize_url(state: Capture::Quickbooks::Oauth.state_for(current_user)),
                allow_other_host: true
  end

  # Back from Intuit with a code and the company's realm id.
  def callback
    return redirect_to(admin_integrations_path, alert: "QuickBooks reported: #{params[:error]}") if params[:error].present?

    user = Capture::Quickbooks::Oauth.user_from_state(params[:state])
    return redirect_to(admin_integrations_path, alert: "That authorisation did not come from here, or it has expired.") if user.nil?
    realm = params[:realmId].presence or return redirect_to(admin_integrations_path, alert: "Intuit did not say which company this is.")

    tokens = Capture::Quickbooks::Oauth.exchange(params[:code])
    integration = Integration.find_by(provider: "quickbooks") || Integration.connect!("quickbooks", user: user).first
    integration.update!(external_id: realm, connected_by: integration.connected_by || user)
    integration.store_tokens!(tokens)
    AuditLog.record("integration.authorised", user: user, subject: integration, provider: "quickbooks", realm: realm)

    QuickbooksSyncJob.perform_later(integration.id)
    redirect_to admin_integrations_path, notice: "QuickBooks connected. Reading what has changed since last week."
  rescue Capture::Quickbooks::Oauth::Error => e
    redirect_to admin_integrations_path, alert: e.message
  end

  # Intuit tells us something changed; we ask it what. The notification itself is not
  # trusted for content — only as a nudge to poll — so a forged one costs nothing but a
  # wasted sweep, and we still refuse it unless it is signed.
  def webhook
    return head :unauthorized unless signed?

    integration = Integration.find_by(provider: "quickbooks")
    QuickbooksSyncJob.perform_later(integration.id) if integration&.enabled?
    head :ok
  end

  private

  # Not an endless method with a modifier: `def x = y unless c` evaluates the guard at
  # class level, where current_user does not exist. This is the second time that shape
  # has silently disabled a check, so it is spelled out.
  def admins_only
    redirect_to(root_path, alert: "Admins only.") unless current_user&.admin?
  end

  def signed?
    verifier = Capture::Quickbooks::Config.webhook_verifier
    signature = request.headers["intuit-signature"]
    return false if verifier.blank? || signature.blank?
    expected = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", verifier, request.raw_post))
    ActiveSupport::SecurityUtils.secure_compare(expected, signature)
  end
end
