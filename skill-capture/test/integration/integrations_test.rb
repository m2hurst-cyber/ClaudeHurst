require "test_helper"

class IntegrationsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup { @admin = make_user(role: "admin") }

  # ---------- the catalogue ----------

  test "ten systems, across the three kinds a finance firm runs on" do
    all = Capture::Integrations.all
    assert_equal 10, all.size
    assert_equal %w[accounting crm erp].sort, all.map(&:category).uniq.sort
    assert_operator all.count { |p| p.category == "erp" }, :>=, 4
    assert_includes all.map(&:name), "Oracle NetSuite"
    assert_includes all.map(&:name), "Salesforce"
    assert_includes all.map(&:name), "QuickBooks Online"
  end

  test "every entry carries what the page and the detector need" do
    Capture::Integrations.all.each do |p|
      assert p.name.present? && p.vendor.present?, "#{p.key} is missing a name or vendor"
      assert p.blurb.length > 40, "#{p.key} does not say what it is"
      assert p.docs.to_s.start_with?("https://"), "#{p.key} has no documentation link"
      assert_includes Capture::Integrations::AUTH_LABELS.keys, p.auth, "#{p.key} has an unknown auth kind"
      assert_operator p.actions.size, :>=, 5, "#{p.key} needs a usable step vocabulary"
      assert p.never.any?, "#{p.key} must say what it will not keep"
      p.actions.each do |a|
        assert a["key"].to_s.include?("."), "#{p.key}: #{a['key']} is not a namespaced step"
        assert a["label"].present? && a["domain"].present?, "#{p.key}: #{a['key']} needs a label and an area"
      end
    end
  end

  test "step keys are unique across the whole catalogue" do
    keys = Capture::Integrations.all.flat_map(&:action_keys)
    assert_equal keys.size, keys.uniq.size, "two systems claim the same step key: #{keys.tally.select { |_, n| n > 1 }.keys}"
  end

  # ---------- connecting ----------

  test "connecting issues a token and teaches the system that vocabulary" do
    assert_equal 0, ActionDefinition.where("key LIKE 'bill.%'").count
    integration, token = Integration.connect!("bill", user: @admin)

    assert_match(/\Asc_/, token)
    assert_equal "BILL", integration.name
    assert integration.source.active?
    assert_equal 6, ActionDefinition.where("key LIKE 'bill.%'").count
    assert_equal "Route for approval", ActionDefinition.find_by(key: "bill.route:for_approval").label
    assert AuditLog.where(action: "integration.connected").exists?
  end

  test "a label of your own survives" do
    integration, = Integration.connect!("netsuite", user: @admin, label: "NetSuite (production)")
    assert_equal "NetSuite (production)", integration.name
    assert_equal "NetSuite (production)", integration.source.name
  end

  test "a system outside the catalogue cannot be connected" do
    assert_raises(ArgumentError) { Integration.connect!("not-a-real-erp", user: @admin) }
  end

  test "the same system is not connected twice" do
    Integration.connect!("xero", user: @admin)
    assert_raises(ActiveRecord::RecordInvalid) { Integration.connect!("xero", user: @admin) }
  end

  test "an existing label is left alone when another system claims the same step" do
    ActionDefinition.create!(key: "xero.create:invoice", label: "Raise a sales invoice", domain: "billing")
    Integration.connect!("xero", user: @admin)
    assert_equal "Raise a sales invoice", ActionDefinition.find_by(key: "xero.create:invoice").label,
                 "connecting must not overwrite a name the firm chose"
  end

  # ---------- the switch ----------

  test "switching one off stops its token, and back on starts it again" do
    integration, token = Integration.connect!("salesforce", user: @admin)
    assert Source.authenticate(token)

    integration.switch!(false)
    integration.source.update!(active: false)
    assert_nil Source.authenticate(token), "an integration that is off collects nothing"

    integration.switch!(true)
    integration.source.update!(active: true)
    assert Source.authenticate(token)
  end

  test "it says whether anything is actually arriving" do
    integration, = Integration.connect!("hubspot", user: @admin)
    assert_equal "quiet", integration.state

    UsageEvent.create!(source: integration.source, actor_key: "u-1", session_key: "s1", action_key: "hubspot.create:deal", occurred_at: 5.minutes.ago)
    integration.refresh_counts!
    assert_equal "live", integration.state
    assert_equal 1, integration.event_count

    UsageEvent.update_all(occurred_at: 3.days.ago)
    integration.refresh_counts!
    assert_equal "quiet", integration.state, "collected once is not collecting now"

    integration.switch!(false)
    assert_equal "off", integration.state
  end

  test "disconnecting stops the token but keeps what was collected" do
    integration, = Integration.connect!("sage-intacct", user: @admin)
    UsageEvent.create!(source: integration.source, actor_key: "u-1", session_key: "s1", action_key: "sage.post:journal", occurred_at: 1.hour.ago)

    integration.disconnect!(@admin)
    refute Integration.exists?(provider: "sage-intacct")
    assert_equal 1, UsageEvent.count, "the work it saw is the firm's, not the connector's"
  end

  # ---------- what arrives, and what the detector makes of it ----------

  test "steps from a connected system are mined and read in words" do
    integration, token = Integration.connect!("bill", user: @admin)
    source = Source.authenticate(token)

    3.times do |i|
      Capture::Ingestor.call(source, %w[bill.code:bill bill.route:for_approval bill.approve:bill].each_with_index.map do |key, n|
        { "action" => key, "actor" => { "id" => "u-7" }, "session" => "run-#{i}", "occurred_at" => ((10 - i).hours.ago + n.minutes).iso8601 }
      end)
    end

    pattern = Capture::WorkflowDetector.new(min_occurrences: 2).detect.find { |p| p.steps.first.start_with?("bill.") }
    assert pattern, "a repeated run in the ERP should be found like any other"
    assert_equal ["Code a bill", "Route for approval", "Approve a bill"],
                 ActionDefinition.labels_for(pattern.steps).values,
                 "and read as words, because connecting registered the vocabulary"
  end

  # ---------- the page ----------

  test "an admin sees the catalogue and can connect from it" do
    sign_in @admin
    get admin_integrations_path
    assert_response :success
    assert_match(/Oracle NetSuite/, response.body)
    assert_match(/Never kept/, response.body)

    post admin_integrations_path, params: { provider: "quickbooks", label: "QBO" }
    follow_redirect!
    assert_match(/\Asc_/, flash[:issued_token].to_s)
    assert_match(/connected/, response.body)
    assert_match(%r{/api/v1/events}, response.body, "with somewhere to send events")
  end

  test "the switch flips from the page" do
    integration, = Integration.connect!("workday", user: @admin)
    sign_in @admin
    patch admin_integration_path(integration, enabled: false)
    refute integration.reload.enabled?
    refute integration.source.reload.active?
  end

  test "integrations are an admin's business" do
    sign_in make_user
    get admin_integrations_path
    assert_response :redirect
  end
end
