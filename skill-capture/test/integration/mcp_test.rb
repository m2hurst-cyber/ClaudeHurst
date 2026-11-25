require "test_helper"

# The MCP endpoint: any agent that speaks the protocol can search the library, follow the map, pick up
# the work addressed to it, run a job and report what it cost.
class McpTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    PromotionPolicy.current.update!(initial_stage: "firm")
    Capture::Taxonomy.ensure_defaults!
    Capture::Models.ensure_defaults!
    @admin = make_user(role: "admin", name: "Ada Admin")
    @pm = make_user(role: "member", domains: %w[field-services jobcost], name: "Jordan Pike")
    @agent, @agent_token = Source.issue!(name: "Takeoff agent", kind: "integration")
    @person_token = AddinToken.issue!(user: @pm, host: "Excel").last
    Capture::Playbook.find("roofing-solar").install!(user: @admin)
  end

  def rpc(method, params = nil, token: @agent_token, id: 1)
    body = { jsonrpc: "2.0", id: id, method: method }
    body[:params] = params if params
    post "/mcp", params: body.to_json, headers: { "Authorization" => "Bearer #{token}", "Content-Type" => "application/json" }
    response.parsed_body
  end

  def tool(name, args = {}, token: @agent_token)
    r = rpc("tools/call", { name: name, arguments: args }, token: token)
    raise "rpc error: #{r['error']}" if r["error"]
    r["result"]
  end

  def data(name, args = {}, token: @agent_token) = tool(name, args, token: token)["structuredContent"]

  test "a client initializes, lists ten tools, and gets told what the server is for" do
    r = rpc("initialize", { protocolVersion: "2025-03-26", capabilities: {}, clientInfo: { name: "test", version: "1" } })
    assert_equal "2025-03-26", r.dig("result", "protocolVersion"), "the client's version is echoed back"
    assert_equal "skill-capture", r.dig("result", "serverInfo", "name")
    assert_match(/report what every run cost/, r.dig("result", "instructions"))
    assert_equal({}, rpc("ping").fetch("result"))

    tools = rpc("tools/list").dig("result", "tools")
    assert_equal 10, tools.size
    assert_equal %w[add_job_document complete_task find_route get_job get_skill list_playbooks list_tasks report_usage search_skills start_job],
                 tools.map { |t| t["name"] }.sort
    tools.each do |t|
      assert t["description"].to_s.length > 40, "#{t['name']} needs a description an agent can act on"
      assert_equal "object", t.dig("inputSchema", "type")
    end
    assert_includes rpc("tools/list").dig("result", "tools").find { |t| t["name"] == "search_skills" }.dig("inputSchema", "properties").keys, "level"

    # a notification gets no reply, an unknown method is refused politely
    post "/mcp", params: { jsonrpc: "2.0", method: "notifications/initialized" }.to_json,
         headers: { "Authorization" => "Bearer #{@agent_token}", "Content-Type" => "application/json" }
    assert_response :accepted
    assert_equal(-32_601, rpc("wat").dig("error", "code"))
  end

  test "without a token nothing is served; a GET describes the endpoint" do
    post "/mcp", params: { jsonrpc: "2.0", id: 1, method: "tools/list" }.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :unauthorized
    assert_match(/integration token/, response.parsed_body.dig("error", "message"))
    get "/mcp", headers: { "Authorization" => "Bearer #{@agent_token}" }
    assert_equal 10, response.parsed_body["tools"].size
  end

  test "an agent searches the library, reads a skill and follows the map" do
    found = data("search_skills", { query: "roof", limit: 5 })
    assert_operator found["count"], :>, 0
    assert found["skills"].all? { |s| s["name"].present? && s["title"].present? }

    s = data("get_skill", { name: "survey-the-roof-and-site" })
    assert_equal "survey-the-roof-and-site", s["name"]
    assert_match(/## Steps/, s["skill_md"])
    assert_operator s.dig("estimate", "tokens"), :>, 0
    md = data("get_skill", { name: "survey-the-roof-and-site", markdown: true })
    assert md["markdown"].start_with?("---\nname: survey-the-roof-and-site")

    route = data("find_route", { from: "survey-the-roof-and-site" })
    assert_includes route["next_up"].map { |n| n["name"] }, "price-the-roofing-job"
    chain = data("find_route", { from: "survey-the-roof-and-site", to: "bill-the-roofing-job" })
    assert_equal "survey-the-roof-and-site", chain["skills"].first
    assert_equal "bill-the-roofing-job", chain["skills"].last
    assert_operator chain["directions"].size, :>, 0

    assert_match(/No skill named nope/, tool("get_skill", { name: "nope" })["content"].first["text"])
    assert tool("get_skill", { name: "nope" })["isError"]
  end

  test "a person runs a job end to end: start it, add documents, watch the checks clear" do
    pbs = data("list_playbooks", {}, token: @person_token)
    roofing = pbs["playbooks"].find { |p| p["key"] == "roofing-solar" }
    assert_equal "job", roofing["calls_a_run"]
    assert_includes roofing["branches"].map { |b| b["key"] }, "solar-array"
    detail = data("list_playbooks", { key: "roofing-solar" }, token: @person_token)["playbooks"].first
    assert_includes detail["documents"].map { |d| d["kind"] }, "signed-contract"

    job = data("start_job", { playbook: "roofing-solar", reference: "J-9000",
                              answers: { "solar-array" => "no", "commercial-rfp" => "no", "insurance-claim" => "no",
                                         "subcontracted-work" => "no", "hidden-damage" => "no", "prevailing-wage" => "no",
                                         "maintenance-agreement" => "no", "collections" => "no" } }, token: @person_token)
    assert_equal ["J-9000", "job", 0], [job.dig("job", "reference"), job.dig("job", "called"), job.dig("job", "verified")]
    assert_equal "qualify-the-roofing-lead", job.dig("next", "leg")
    refute_includes job["road"].map { |l| l["leg"] }, "interconnect-the-solar-array", "a branch the job said no to"

    added = data("add_job_document", { reference: "J-9000", kind: "signed-contract", status: "confirmed",
                                       fields: { "signed" => "yes", "contract_value" => "146000", "retainage_pct" => "10" } }, token: @person_token)
    assert_equal "confirmed", added.dig("added", "status")
    contract_leg = added["road"].find { |l| l["leg"] == "contract-the-roofing-job" }
    refute_includes contract_leg["blocking"], "The contract is signed", "the check the document feeds now passes"
    assert_equal 146_000.0, contract_leg.dig("figures", "contract_value")

    again = data("get_job", { reference: "J-9000" }, token: @person_token)
    assert_equal 1, again["documents"].size
    assert_includes again["road"].find { |l| l["leg"] == "survey-the-roof-and-site" }["documents_needed"], "measurement-report"

    # an agent token can't open or read someone's job
    assert_match(/person's add-in token/, tool("get_job", { reference: "J-9000" })["content"].first["text"])
    other = make_user(role: "member", name: "Someone Else")
    assert_match(/belongs to someone else/, tool("get_job", { reference: "J-9000" },
                                                 token: AddinToken.issue!(user: other, host: "Excel").last)["content"].first["text"])
  end

  test "an agent picks up the task addressed to it, finishes it, and the flow hands on" do
    skill = Skill.current("survey-the-roof-and-site")
    flow = Flow.create!(user: @pm, name: "Bid", steps: Flow.normalize_steps([
      { id: "t1", title: "Take off the roof from the drawings", app: "Excel", assignee: "agent:#{@agent.id}", skill_name: skill.name },
      { id: "t2", title: "Price it", app: "Excel", assignee: "me" }
    ]))
    run = FlowRun.start!(flow, user: @pm)

    mine = data("list_tasks")
    assert_equal 1, mine["count"]
    t = mine["tasks"].first
    assert_equal ["Take off the roof from the drawings", run.id, 0], t.values_at("title", "flow_run_id", "step")
    assert t["anticipated"]["tokens"].positive?
    assert_empty data("list_tasks", {}, token: @person_token)["tasks"], "the person's queue is their own"

    done = data("complete_task", { flow_run_id: run.id, step: 0, note: "312 squares over 6 planes",
                                   model: "claude-sonnet-5-5", input_tokens: 14_200, output_tokens: 2_600, duration_ms: 38_000 })
    assert_equal "Price it", done.dig("now", "title")
    assert_equal 16_800, done.dig("spent_so_far", "tokens")
    assert_equal "312 squares over 6 planes", run.reload.steps[0]["note"]
    assert_equal 16_800, SkillRun.where(flow_run: run).sum { |r| r.total_tokens }

    assert_match(/isn't the current task/, tool("complete_task", { flow_run_id: run.id, step: 0 })["content"].first["text"])
    assert_empty data("list_tasks")["tasks"], "the queue empties as work is finished"
  end

  test "an agent reports what a run cost, and can hand over the macro that replaces it" do
    r = data("report_usage", { skill: "install-the-roof", model: "claude-opus-5-5", input_tokens: 20_000,
                               output_tokens: 3_000, duration_ms: 44_000, status: "succeeded" })
    assert_equal 23_000, r.dig("recorded", "tokens")
    assert_in_delta 0.525, r.dig("recorded", "cost"), 0.001
    assert_equal 1, r.dig("usage", "runs")
    assert_equal "linear", SkillRun.order(:id).last.nature

    code = "async function run(context) { const s = context.workbook.worksheets.getActiveWorksheet(); return 'logged'; }"
    with_macro = data("report_usage", { skill: "install-the-roof", model: "claude-haiku-5-5", input_tokens: 2_000,
                                        output_tokens: 400, macro_code: code, macro_language: "addin_js" })
    review = MacroReview.find(with_macro.dig("macro_review", "id"))
    assert_equal ["ai", "proposed", code], [review.written_by, review.status, review.code]
    assert_match(/over MCP/, review.reason)
    assert_match(/No skill named nope/, tool("report_usage", { skill: "nope" })["content"].first["text"])
  end

  test "an admin can see how to connect an agent" do
    sign_in @admin
    get admin_sources_path
    assert_select "section#mcp pre", text: /"url": "http:\/\/www.example.com\/mcp"/
    assert_select "section#mcp code", text: "complete_task"
  end

  test "every call is in the audit log, and a missing argument is refused before anything happens" do
    data("search_skills", { query: "roof" })
    log = AuditLog.order(:id).last
    assert_equal ["mcp.call", "search_skills", @agent.id], [log.action, log.metadata["tool"], log.source_id]
    assert_match(/needs skill/, tool("report_usage", {})["content"].first["text"])
    assert_equal "mcp.refused", AuditLog.order(:id).last.action
  end
end
