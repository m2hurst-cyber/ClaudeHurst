require "test_helper"

class ConnectionsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @me = make_user(name: "Sam Ortiz")
    @other = make_user(name: "Rae Reviewer")
  end

  # ---------- the switch ----------

  test "switching a connection off stops it answering, without losing the key" do
    record, token = AddinToken.issue!(user: @me, kind: "mcp", name: "Claude Desktop")
    assert_equal record, AddinToken.authenticate(token)

    record.switch!(false)
    assert_nil AddinToken.authenticate(token), "an agent that is off cannot reach anything"

    record.switch!(true)
    assert_equal record, AddinToken.authenticate(token), "and the same key works again when it is switched back"
  end

  test "revoking is final where switching off is not" do
    record, token = AddinToken.issue!(user: @me, kind: "mcp", name: "Cursor")
    record.revoke!
    assert_nil AddinToken.authenticate(token)
    record.switch!(true)
    assert_nil AddinToken.authenticate(token), "switching a revoked key on does not bring it back"
  end

  test "a connection says which of the three states it is in" do
    record, = AddinToken.issue!(user: @me, kind: "mcp", name: "Agent")
    assert_equal "on", record.state

    record.update!(last_used_at: 2.minutes.ago)
    assert_equal "online", record.state
    assert record.online?

    record.update!(last_used_at: 2.hours.ago)
    assert_equal "on", record.state, "used this morning is not online"

    record.switch!(false)
    assert_equal "off", record.state
    refute record.online?, "something switched off is never online"
  end

  test "a connection is named after whatever it can be named after" do
    assert_equal "Claude Desktop", AddinToken.new(kind: "mcp", name: "Claude Desktop").label
    assert_equal "Excel", AddinToken.new(kind: "office", platform: "Excel").label
    assert_equal "Agent", AddinToken.new(kind: "mcp").label
    assert_equal "Office add-in", AddinToken.new(kind: "office").label
  end

  # ---------- the page ----------

  test "the page shows what can reach your work, and its state" do
    AddinToken.issue!(user: @me, kind: "mcp", name: "Claude Desktop")
    office, = AddinToken.issue!(user: @me, kind: "office", platform: "Excel")
    office.update!(last_used_at: 1.minute.ago)
    sign_in @me

    get connections_path
    assert_response :success
    assert_match(/Claude Desktop/, response.body)
    assert_match(/Online/, response.body)
    assert_select "button[aria-pressed=true]", 2
  end

  test "the switch says which way it is, and what pressing it does" do
    record, = AddinToken.issue!(user: @me, kind: "mcp", name: "Claude Desktop")
    sign_in @me

    get connections_path
    assert_select "button[aria-label=?]", "Turn Claude Desktop off"
    assert_select "button[aria-pressed=true] span", text: "on"

    record.switch!(false)
    get connections_path
    assert_select "button[aria-label=?]", "Turn Claude Desktop on"
    assert_select "button[aria-pressed=false]"
  end

  test "pressing the switch flips it" do
    record, = AddinToken.issue!(user: @me, kind: "mcp", name: "Claude Desktop")
    sign_in @me

    patch connection_path(record, enabled: false)
    assert_redirected_to connections_path
    refute record.reload.enabled?
    assert AuditLog.where(action: "connection.switched").exists?

    patch connection_path(record, enabled: true)
    assert record.reload.enabled?
  end

  test "creating a key shows it once and never again" do
    sign_in @me
    post connections_path, params: { name: "The close bot" }
    follow_redirect!

    body = response.body
    assert_match(/sca_/, body, "the key is shown once")
    assert_match(/only time it is shown/, body)
    assert_match(/skill-capture/, body, "with something to paste into an agent")

    get connections_path
    assert_no_match(/sca_/, response.body, "and not again on the next visit")
  end

  test "an issued key works and belongs to the person who made it" do
    sign_in @me
    post connections_path, params: { name: "The close bot" }
    token = flash[:issued_token]

    record = AddinToken.authenticate(token)
    assert_equal @me, record.user
    assert_equal "mcp", record.kind
    assert_equal "The close bot", record.name
  end

  test "an unnamed key still gets a name" do
    sign_in @me
    post connections_path, params: { name: "  " }
    assert_equal "Agent", @me.addin_tokens.last.name
  end

  # ---------- it is yours alone ----------

  test "nobody switches or revokes anyone else's connection" do
    record, = AddinToken.issue!(user: @other, kind: "mcp", name: "Theirs")
    sign_in @me

    patch connection_path(record, enabled: false)
    assert_redirected_to connections_path
    assert record.reload.enabled?, "untouched"

    delete connection_path(record)
    assert_nil record.reload.revoked_at
  end

  test "revoked connections leave the page" do
    record, = AddinToken.issue!(user: @me, kind: "mcp", name: "Claude Desktop")
    sign_in @me

    delete connection_path(record)
    assert record.reload.revoked_at.present?
    get connections_path
    assert_select "li", text: /Claude Desktop/, count: 0
  end

  test "the firm's collectors are shown to admins and to nobody else" do
    Source.issue!(name: "Nightly collector", kind: "integration")
    sign_in @me
    get connections_path
    assert_no_match(/Nightly collector/, response.body)

    sign_in make_user(role: "admin")
    get connections_path
    assert_match(/Nightly collector/, response.body)
    assert_match(/The firm's collectors/, response.body)
  end
end
