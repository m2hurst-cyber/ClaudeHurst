require "test_helper"

# Agents report token/time/model usage per skill run (intensity); flows sequence tasks across apps,
# people and agents, each handing off to the next when done.
class FlowsAndUsageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    PromotionPolicy.current.update!(initial_stage: "firm")
    @admin = make_user(role: "admin", name: "Ada Admin")
    @rae = make_user(role: "member", domains: %w[finance], name: "Rae")
    @dee = make_user(role: "member", domains: %w[finance], name: "Dee")
    @agent, @agent_token = Source.issue!(name: "Research agent", kind: "integration")
    @skills = %w[charts-to-ppt-appendix board-deck-design light-one heavy-one].map { |n| publish(n) }
  end

  def publish(name)
    steps = ["x.#{name}:a", "x.#{name}:b"]
    c = SkillCandidate.create!(signature: SkillCandidate.signature_for(steps), steps: steps, domain: "finance", status: "drafted",
                               draft_name: name, draft_title: name.titleize, draft_description: "Does #{name}.", draft_body: "1. a\n2. b")
    Capture::Publisher.publish!(c, reviewer: @admin)
  end

  def agent_headers = { "Authorization" => "Bearer #{@agent_token}", "Content-Type" => "application/json" }
  def addin_headers(u, host) = { "Authorization" => "Bearer #{AddinToken.issue!(user: u, host: host).last}", "Content-Type" => "application/json" }

  test "agents report each run; the skill shows tokens, time, model and intensity" do
    [[1000, 500, 20_000, "model-a"], [3000, 1000, 40_000, "model-a"], [2000, 2000, nil, "model-b"]].each do |i, o, ms, m|
      post "/api/v1/skills/charts-to-ppt-appendix/runs", params: { model: m, input_tokens: i, output_tokens: o, duration_ms: ms }.compact.to_json, headers: agent_headers
      assert_response :created
    end
    post "/api/v1/skills/charts-to-ppt-appendix/runs", params: { model: "model-b", input_tokens: 10, output_tokens: 10, started_at: "2026-11-24T10:00:00Z", finished_at: "2026-11-24T10:01:00Z", status: "failed" }.to_json, headers: agent_headers
    u = response.parsed_body["usage"]
    assert_equal [4, 0.75, 2380, 40.0], [u["runs"], u["success_rate"], u["avg_tokens"], u["avg_seconds"].round(1)]
    assert_equal %w[model-a model-b], u["models"].map { |m| m["model"] }.sort
    assert_equal 60_000, SkillRun.order(:id).last.duration_ms

    post "/api/v1/skills/charts-to-ppt-appendix/runs", params: { input_tokens: -5 }.to_json, headers: agent_headers
    assert_response :unprocessable_entity
    post "/api/v1/skills/nope/runs", params: {}.to_json, headers: agent_headers
    assert_response :not_found
    post "/api/v1/skills/charts-to-ppt-appendix/runs", params: {}.to_json
    assert_response :unauthorized

    # Intensity relative to other skills
    SkillRun.create!(skill_name: "light-one", agent: "x", input_tokens: 10, output_tokens: 10)
    SkillRun.create!(skill_name: "heavy-one", agent: "x", input_tokens: 90_000, output_tokens: 10_000)
    stats = Capture::Intensity.for_names(%w[light-one charts-to-ppt-appendix heavy-one])
    assert_equal %w[light moderate heavy], %w[light-one charts-to-ppt-appendix heavy-one].map { |n| stats[n][:intensity] }

    # The add-in can report too; agents see usage and where to report in the bundle
    post "/api/v1/addin/skills/light-one/runs", params: { model: "model-c", input_tokens: 5, output_tokens: 5 }.to_json, headers: addin_headers(@rae, "Excel")
    assert_response :created
    assert_equal "Office add-in (Excel)", SkillRun.order(:id).last.agent
    get "/api/v1/bundles/charts-to-ppt-appendix", headers: agent_headers
    assert_equal "/api/v1/skills/charts-to-ppt-appendix/runs", response.parsed_body.dig("report_usage", "url")
    assert_equal 4, response.parsed_body.dig("usage", "runs")

    sign_in @rae
    get skill_path(Skill.current("charts-to-ppt-appendix"))
    assert_select "#agent-usage dd", text: /2,380/
    assert_select "#agent-usage td", text: "model-a"
  end

  test "the research-report template: nine tasks across Excel, an agent, Word and PowerPoint, linked to skills" do
    f = Flow.from_template("research-report", user: @rae, agent: @agent)
    assert f.save, f.errors.full_messages.inspect
    assert_equal 9, f.steps.size
    assert_equal %w[Excel Excel Excel Excel Excel Agent Word PowerPoint PowerPoint], f.steps.map { |s| s["app"] }
    assert_equal "agent:#{@agent.id}", f.steps[1]["assignee"]
    assert_equal [nil, "board-deck-design", "charts-to-ppt-appendix"], f.steps.values_at(0, 7, 8).map { |s| s["skill_name"] }
    f.steps << f.steps.last.merge("id" => f.steps.last["id"])
    refute f.valid?, "duplicate ids"
  end

  test "a run hands off in order: person in Excel → agent → person in PowerPoint, only to the right app" do
    flow = Flow.create!(user: @rae, name: "Data to deck", steps: [
      { "id" => "a1", "title" => "Collect data", "app" => "Excel", "assignee" => "me" },
      { "id" => "a2", "title" => "Regression on Y", "app" => "Excel", "assignee" => "agent:#{@agent.id}", "skill_name" => "light-one" },
      { "id" => "a3", "title" => "Appendix", "app" => "PowerPoint", "assignee" => "user:#{@dee.id}", "skill_name" => "charts-to-ppt-appendix" }
    ])
    post "/api/v1/addin/flow_runs", params: { flow_id: flow.id }.to_json, headers: addin_headers(@rae, "Excel")
    run = FlowRun.find(response.parsed_body["id"])
    assert_equal %w[ready pending pending], run.steps.map { |s| s["state"] }

    # Rae's Excel add-in gets task 1
    get "/api/v1/addin/commands", params: { host: "Excel" }, headers: addin_headers(@rae, "Excel")
    assert_equal ["Collect data"], response.parsed_body.map { |c| c.dig("task", "title") }
    post "/api/v1/addin/flow_runs/#{run.id}/complete?step=1", params: { note: "x" }.to_json, headers: addin_headers(@rae, "Excel")
    assert_response :unprocessable_entity, "not the current task"
    post "/api/v1/addin/flow_runs/#{run.id}/complete?step=0", params: { note: "Raw sheet: Data" }.to_json, headers: addin_headers(@rae, "Excel")
    assert_equal 1, response.parsed_body["current_index"]

    # The agent picks up task 2 with a URL to complete it, and reports usage
    get "/api/v1/commands", headers: agent_headers
    task = response.parsed_body.first["task"]
    assert_equal ["Regression on Y", "Raw sheet: Data"], [task["title"], task.dig("previous", "note")]
    assert_match %r{/api/v1/flow_runs/#{run.id}/complete\?step=1\z}, task["complete_url"]
    post "/api/v1/flow_runs/#{run.id}/complete?step=1", params: { note: "Coefficients in Regression!B2", usage: { model: "model-a", input_tokens: 4000, output_tokens: 900, duration_ms: 30_000 } }.to_json, headers: agent_headers
    assert_response :success
    assert_equal ["light-one", "Research agent", run.id], SkillRun.order(:id).last.values_at(:skill_name, :agent, :flow_run_id)

    # Task 3 is Dee's, in PowerPoint: her Excel add-in doesn't get it, her PowerPoint add-in does
    get "/api/v1/addin/commands", params: { host: "Excel" }, headers: addin_headers(@dee, "Excel")
    assert_empty response.parsed_body
    get "/api/v1/addin/commands", params: { host: "PowerPoint" }, headers: addin_headers(@dee, "PowerPoint")
    assert_equal "Appendix", response.parsed_body.first.dig("task", "title")
    assert_equal ["charts-to-ppt-appendix"], response.parsed_body.first["bundles"].map { |b| b["name"] }
    post "/api/v1/addin/flow_runs/#{run.id}/complete?step=2", params: {}.to_json, headers: addin_headers(@rae, "PowerPoint")
    assert_response :unprocessable_entity, "Rae isn't the doer"

    sign_in @dee
    get flow_run_path(run)
    assert_select "button", text: /Done: hand off to finish/
    post complete_flow_run_path(run, step: 2), params: { note: "Appendix slides 14–22" }
    assert_equal "completed", run.reload.status
    assert Notification.exists?(user: @rae, kind: "flow", title: "“Data to deck” is complete")
    get flow_run_path(run)
    assert_select "svg[aria-label*='3. Appendix: done']"
  end

  test "console: process map editor saves reordered steps; template and blank maps" do
    sign_in @rae
    get new_flow_path(template: "research-report")
    flow = Flow.last
    assert_redirected_to flow_path(flow)
    get flow_path(flow)
    assert_select "[data-controller=flow-map]"
    assert_select "[data-flow-map-target=paletteItem]", minimum: 2
    steps = flow.steps.reverse.each_with_index.map { |s, i| i.zero? ? s.merge("app" => "Word") : s }
    patch flow_path(flow, format: :json), params: { name: "Reversed", steps: steps }.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :success
    assert_equal ["Reversed", "Word", "Collect data"], [flow.reload.name, flow.steps.first["app"], flow.steps.last["title"]]
    patch flow_path(flow, format: :json), params: { steps: [] }.to_json, headers: { "Content-Type" => "application/json" }
    assert_response :unprocessable_entity
    post run_flow_path(flow)
    assert_redirected_to flow_run_path(FlowRun.last)
    get flows_path
    assert_select "a", text: "Reversed"
    sign_in @dee
    get flow_path(flow)
    assert_response :redirect
  end
end
