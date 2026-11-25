require "test_helper"

class QuickbooksTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { @admin = make_user(role: "admin") }

  def connected(realm: "4620816365", refresh: "rt-1", expires: 1.hour.from_now)
    integration = Integration.find_by(provider: "quickbooks") || Integration.connect!("quickbooks", user: @admin).first
    integration.update!(external_id: realm)
    integration.store_tokens!(access_token: "at-1", refresh_token: refresh, expires_at: expires)
    integration
  end

  class FakeHttp
    attr_reader :calls
    def initialize(responses) = (@responses = responses; @calls = [])
    def start(_h, _p, **_o) = yield(self)
    def request(req)
      @calls << [req.method, req.path + (req.uri.query ? "?#{req.uri.query}" : ""), req.body]
      _key, (code, body) = @responses.find { |pattern, _| req.path.match?(pattern) }
      raise "no stub for #{req.path}" if code.nil?
      Struct.new(:code, :body).new(code.to_s, body.is_a?(String) ? body : JSON.generate(body))
    end
  end

  # ---------- the change feed becomes steps ----------

  CDC = {
    "CDCResponse" => [{ "QueryResponse" => [
      { "Invoice" => [{ "Id" => "1", "MetaData" => { "CreateTime" => "2026-11-20T09:00:00-08:00", "LastUpdatedTime" => "2026-11-20T09:00:00-08:00" } }] },
      { "Payment" => [{ "Id" => "2", "MetaData" => { "LastUpdatedTime" => "2026-11-20T09:05:00-08:00" } }] },
      { "Bill" => [{ "Id" => "3", "status" => "Create", "MetaData" => { "LastUpdatedTime" => "2026-11-20T09:10:00-08:00" } }] },
      { "TimeActivity" => [{ "Id" => "9", "MetaData" => { "LastUpdatedTime" => "2026-11-20T09:20:00-08:00" } }] }
    ] }]
  }.freeze

  test "changed records become steps in this firm's own vocabulary" do
    integration = connected
    events = Capture::Quickbooks::Sync.events_from(CDC, integration)

    assert_equal %w[quickbooks.create:invoice quickbooks.receive:payment quickbooks.enter:bill], events.map { |e| e["action"] }
    assert events.all? { |e| e["action"].in?(Capture::Integrations.find("quickbooks").action_keys) },
           "every step must be one the catalogue declared, or no reviewer can read it"
  end

  test "a record we have no step for is skipped rather than guessed at" do
    events = Capture::Quickbooks::Sync.events_from(CDC, connected)
    refute events.any? { |e| e["action"].include?("TimeActivity") }
    assert_equal 3, events.size
  end

  test "steps are attributed to the company, because Intuit does not say who did it" do
    integration = connected(realm: "99")
    event = Capture::Quickbooks::Sync.events_from(CDC, integration).first

    assert_equal "qbo:99", event.dig("actor", "id")
    assert_equal "QuickBooks Online", event.dig("context", "app")
    assert_equal "qbo-99-2026-11-20", event["session"], "a day's bookkeeping is one stretch of work"
  end

  test "a feed we cannot read yields nothing instead of raising" do
    assert_empty Capture::Quickbooks::Sync.events_from({ "CDCResponse" => "nonsense" }, connected)
    assert_empty Capture::Quickbooks::Sync.events_from(nil, connected)
  end

  test "a sweep ingests, records where it got to, and counts" do
    integration = connected
    http = FakeHttp.new({ %r{/cdc} => [200, CDC] })
    Capture::Quickbooks::Sync.call(integration, client: Capture::Quickbooks::Client.new(integration, http: http))

    assert_equal 3, UsageEvent.where(source_id: integration.source_id).count
    assert integration.reload.last_synced_at.present?
    assert_nil integration.last_sync_error
    assert_equal 3, integration.event_count
    assert AuditLog.where(action: "integration.synced").exists?
  end

  test "the sweep asks only for the window Intuit allows" do
    integration = connected
    integration.update!(last_synced_at: 90.days.ago)
    http = FakeHttp.new({ %r{/cdc} => [200, CDC] })
    Capture::Quickbooks::Client.new(integration, http: http).changes_since(integration.last_synced_at)

    asked = CGI.parse(URI(http.calls.first[1]).query)["changedSince"].first
    assert_operator Time.parse(asked), :>, 31.days.ago, "a long gap resumes at the edge of the window, not before it"
    assert_includes http.calls.first[1], "minorversion="
  end

  # ---------- tokens ----------

  test "a rotated refresh token is stored, or the connection dies in a month" do
    integration = connected(refresh: "old-refresh", expires: 30.seconds.from_now)
    http = FakeHttp.new({
      %r{/tokens/bearer} => [200, { "access_token" => "at-2", "refresh_token" => "new-refresh", "expires_in" => 3600 }],
      %r{/cdc} => [200, CDC]
    })
    Capture::Quickbooks::Client.new(integration, http: http).changes_since(nil)

    assert_equal "new-refresh", integration.reload.credentials_hash["refresh_token"]
    assert_equal "at-2", integration.credentials_hash["access_token"]
    assert_operator integration.token_expires_at, :>, 50.minutes.from_now
  end

  test "a token still good is not refreshed" do
    integration = connected(expires: 2.hours.from_now)
    http = FakeHttp.new({ %r{/cdc} => [200, CDC] })
    Capture::Quickbooks::Client.new(integration, http: http).changes_since(nil)
    assert http.calls.none? { |_, path, _| path.include?("tokens/bearer") }
  end

  test "tokens are never stored in the clear" do
    integration = connected(refresh: "rt-secret")
    raw = Integration.connection.select_value("SELECT credentials FROM integrations WHERE id = #{integration.id}")
    refute_includes raw.to_s, "rt-secret"
    assert_equal "rt-secret", integration.reload.credentials_hash["refresh_token"]
  end

  test "Intuit's refusals are said in words, and kept on the integration" do
    integration = connected
    http = FakeHttp.new({ %r{/cdc} => [401, { "fault" => "x" }] })
    error = assert_raises(Capture::Quickbooks::Client::Error) do
      Capture::Quickbooks::Sync.call(integration, client: Capture::Quickbooks::Client.new(integration, http: http))
    end
    assert_match(/Reconnect/, error.message)
    assert_match(/Reconnect/, integration.reload.last_sync_error)
  end

  # ---------- the round trip ----------

  test "the state coming back has to be one we signed, and recently" do
    state = Capture::Quickbooks::Oauth.state_for(@admin)
    assert_equal @admin, Capture::Quickbooks::Oauth.user_from_state(state)
    assert_nil Capture::Quickbooks::Oauth.user_from_state("forged")
    travel 2.hours do
      assert_nil Capture::Quickbooks::Oauth.user_from_state(state), "an hour-old authorisation is not accepted"
    end
  end

  test "a callback without a trustworthy state connects nothing" do
    sign_in @admin
    get admin_quickbooks_callback_path(code: "c", realmId: "123", state: "forged")
    assert_redirected_to admin_integrations_path
    assert_equal 0, Integration.where(provider: "quickbooks").count
  end

  test "connecting says what is missing rather than failing at Intuit" do
    sign_in @admin
    get admin_quickbooks_connect_path
    assert_redirected_to admin_integrations_path
    assert_match(/QUICKBOOKS_CLIENT_ID/, flash[:alert])
  end

  # ---------- the webhook ----------

  test "an unsigned notification is refused" do
    post quickbooks_webhook_path, params: { eventNotifications: [] }, as: :json
    assert_response :unauthorized
  end

  test "a correctly signed notification is accepted and only nudges a poll" do
    connected
    body = { eventNotifications: [{ realmId: "4620816365" }] }.to_json
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", "verifier-token", body))

    ENV["QUICKBOOKS_WEBHOOK_VERIFIER"] = "verifier-token"
    post quickbooks_webhook_path, params: body, headers: { "intuit-signature" => signature, "CONTENT_TYPE" => "application/json" }
    assert_response :ok
  ensure
    ENV.delete("QUICKBOOKS_WEBHOOK_VERIFIER")
  end

  test "a signature for different content is refused" do
    ENV["QUICKBOOKS_WEBHOOK_VERIFIER"] = "verifier-token"
    signature = Base64.strict_encode64(OpenSSL::HMAC.digest("SHA256", "verifier-token", "something else"))
    post quickbooks_webhook_path, params: { eventNotifications: [] }.to_json,
         headers: { "intuit-signature" => signature, "CONTENT_TYPE" => "application/json" }
    assert_response :unauthorized
  ensure
    ENV.delete("QUICKBOOKS_WEBHOOK_VERIFIER")
  end

  # ---------- the thing that must not be forgotten ----------

  test "the endpoints are flagged unverified until someone checks them" do
    refute Capture::Quickbooks::Config.verified?,
           "when the endpoints have been checked against Intuit's documentation, set verified: true in config/quickbooks.yml and this test changes with it"
  end
end
